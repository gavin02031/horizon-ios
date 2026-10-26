//! The first *embedded* iOS Metal surface. SwiftUI owns UIApplication and
//! provides a retained UIView with a CAMetalLayer. This does not launch winit.
//!
//! This scene intentionally renders a procedural GPU diagnostic, NOT Minecraft
//! chunks. The existing game.rs Game/Renderer still require Arc<winit::Window>.
//! Replacing the diagnostic pipeline with gfx::Renderer requires extracting
//! that window dependency and game tick ownership. See METAL-MILESTONE.md.
use std::{ffi::c_void, ptr::NonNull, sync::{Mutex, OnceLock}};
use horizon_client::gamepad::{self, Button, Edges, PadSettings, PadState};
use raw_window_handle::{RawDisplayHandle, RawWindowHandle, UiKitDisplayHandle, UiKitWindowHandle};
use wgpu::util::DeviceExt;

static SCENE: OnceLock<Mutex<NativeScene>> = OnceLock::new();
fn scene() -> &'static Mutex<NativeScene> {
    SCENE.get_or_init(|| Mutex::new(NativeScene::default()))
}

#[derive(Default)]
struct NativeScene {
    metal: Option<MetalSurface>,
    touch: PadState,
    physical: PadState,
    edges: Edges,
    preview_x: f32,
    preview_z: f32,
    yaw: f32,
    pitch: f32,
    ticks: u64,
    carry: f32,
    hotbar: usize,
    /// Captures the same actions / edges as the desktop Horizon pad mapper.
    last_action: Option<&'static str>,
}

struct MetalSurface {
    _instance: wgpu::Instance,
    surface: wgpu::Surface<'static>,
    _adapter: wgpu::Adapter,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    pipeline: wgpu::RenderPipeline,
    globals: wgpu::Buffer,
    binding: wgpu::BindGroup,
    time: f32,
}

const SHADER: &str = r#"
struct Globals { dims: vec4<f32>, camera: vec4<f32> };
@group(0) @binding(0) var<uniform> scene: Globals;

@vertex
fn vertex(@builtin(vertex_index) n: u32) -> @builtin(position) vec4<f32> {
    var coords = array<vec2<f32>, 3>(
        vec2<f32>(-1.0, -1.0), vec2<f32>(3.0, -1.0), vec2<f32>(-1.0, 3.0));
    return vec4<f32>(coords[n], 0.0, 1.0);
}
@fragment
fn fragment(@builtin(position) pixel: vec4<f32>) -> @location(0) vec4<f32> {
    let uv = pixel.xy / scene.dims.xy;
    let t = scene.dims.z;
    let x = uv.x * 35.0 + scene.camera.x * 0.45;
    let hills = 0.64 + 0.052 * sin(x * 0.53) + 0.024 * sin(x * 1.41 + 0.8);
    let sky = mix(vec3<f32>(0.055, 0.12, 0.25),
                  vec3<f32>(0.18, 0.42, 0.63), clamp(uv.y * 1.9, 0.0, 1.0));
    let block = floor(x);
    let shade = 0.72 + 0.12 * fract(sin(block * 18.23) * 43758.5);
    let terrain = vec3<f32>(0.07, 0.21, 0.22) * shade;
    let grass = vec3<f32>(0.11, 0.46, 0.36) * shade;
    let blockY = floor(uv.y * 28.0) / 28.0;
    let green = select(terrain, grass, abs(blockY - hills) < 0.038);
    let ground = select(sky, green, uv.y > hills);
    let grid = (1.0 - step(0.035, fract(x))) * 0.08 +
               (1.0 - step(0.04, fract(uv.y * 28.0))) * 0.05;
    let pulse = 0.015 * sin(t * 0.4);
    return vec4<f32>(ground + vec3<f32>(grid + pulse), 1.0);
}
"#;

fn f32_bytes(values: &[f32;8]) -> [u8;32] {
    let mut out=[0u8;32];
    for (i,v) in values.iter().enumerate() {
        out[4*i..4*i+4].copy_from_slice(&v.to_ne_bytes());
    }
    out
}

impl MetalSurface {
    fn new(view: *mut c_void, width:u32, height:u32) -> Result<Self, String> {
        let view = NonNull::new(view).ok_or("missing UIKit view")?;
        let mut descriptor = wgpu::InstanceDescriptor::new_without_display_handle();
        descriptor.backends = wgpu::Backends::METAL;
        let instance=wgpu::Instance::new(descriptor);
        let target = wgpu::SurfaceTargetUnsafe::RawHandle {
            raw_window_handle: RawWindowHandle::UiKit(UiKitWindowHandle::new(view)),
            raw_display_handle: Some(RawDisplayHandle::UiKit(UiKitDisplayHandle::new())),
        };
        // SAFETY: the Swift coordinator retains the UIView/CAMetalLayer until
        // horizon_ios_metal_close drops this surface. Calls occur on the main
        // run loop, and no GPU surface survives UIViewRepresentable dismantle.
        let surface = unsafe { instance.create_surface_unsafe(target) }
            .map_err(|e| format!("UIKit Metal surface: {e}"))?;
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            compatible_surface: Some(&surface),
            power_preference: wgpu::PowerPreference::HighPerformance,
            force_fallback_adapter: false,
            ..Default::default()
        })).map_err(|e| format!("Metal adapter: {e}"))?;
        let (device,queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("Horizon iOS Metal device"),
            required_features: wgpu::Features::empty(),
            required_limits: adapter.limits(),
            ..Default::default()
        })).map_err(|e| format!("Metal device: {e}"))?;
        let mut config=surface.get_default_config(&adapter,width.max(1),height.max(1))
            .ok_or("No supported Metal surface configuration")?;
        config.format = if surface.get_capabilities(&adapter).formats.contains(&wgpu::TextureFormat::Bgra8Unorm) {
            wgpu::TextureFormat::Bgra8Unorm
        } else { config.format };
        config.present_mode=wgpu::PresentMode::Fifo;
        surface.configure(&device,&config);
        let shader=device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label:Some("iOS Metal surface verification"),
            source:wgpu::ShaderSource::Wgsl(SHADER.into()),
        });
        let globals=device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label:Some("iOS preview frame uniforms"),
            contents:&[0u8;32],
            usage:wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });
        let layout=device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label:Some("iOS scene globals"),
            entries:&[wgpu::BindGroupLayoutEntry {
                binding:0,visibility:wgpu::ShaderStages::FRAGMENT,
                ty:wgpu::BindingType::Buffer {
                    ty:wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset:false,min_binding_size:None,
                },count:None,
            }],
        });
        let binding=device.create_bind_group(&wgpu::BindGroupDescriptor {
            label:Some("iOS preview binding"),layout:&layout,
            entries:&[wgpu::BindGroupEntry {binding:0,resource:globals.as_entire_binding()}],
        });
        let pipeline_layout=device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label:Some("iOS diagnostic pipeline"),
            bind_group_layouts:&[Some(&layout)],
            ..Default::default()
        });
        let pipeline=device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label:Some("iOS Metal scene diagnostic"),
            layout:Some(&pipeline_layout),
            vertex:wgpu::VertexState {
                module:&shader,entry_point:Some("vertex"),
                buffers:&[],compilation_options:Default::default(),
            },
            fragment:Some(wgpu::FragmentState {
                module:&shader,entry_point:Some("fragment"),
                targets:&[Some(wgpu::ColorTargetState {
                    format:config.format,
                    blend:None,write_mask:wgpu::ColorWrites::ALL,
                })],
                compilation_options:Default::default(),
            }),
            primitive:wgpu::PrimitiveState::default(),
            depth_stencil:None,
            multisample:wgpu::MultisampleState::default(),
            multiview_mask:None,cache:None,
        });
        Ok(Self{_instance:instance,surface,_adapter:adapter,device,queue,config,pipeline,globals,binding,time:0.0})
    }
    fn resize(&mut self,width:u32,height:u32) {
        let (width,height)=(width.max(1),height.max(1));
        if self.config.width==width && self.config.height==height{return;}
        self.config.width=width;self.config.height=height;
        self.surface.configure(&self.device,&self.config);
    }
    fn draw(&mut self,dt:f32,x:f32,z:f32,yaw:f32,pitch:f32)->bool {
        self.time+=dt;
        let frame=match self.surface.get_current_texture() {
            wgpu::CurrentSurfaceTexture::Success(frame)
            | wgpu::CurrentSurfaceTexture::Suboptimal(frame) => frame,
            wgpu::CurrentSurfaceTexture::Outdated
            | wgpu::CurrentSurfaceTexture::Lost => {
                self.surface.configure(&self.device,&self.config);
                return true;
            },
            wgpu::CurrentSurfaceTexture::Timeout
            | wgpu::CurrentSurfaceTexture::Occluded => return true,
            _ => return false,
        };
        let uniforms=[
            self.config.width as f32,self.config.height as f32,self.time,0.0,
            x,z,yaw,pitch
        ];
        self.queue.write_buffer(&self.globals,0,&f32_bytes(&uniforms));
        let view=frame.texture.create_view(&wgpu::TextureViewDescriptor::default());
        let mut encoder=self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label:Some("Horizon iOS Metal draw")
        });
        {
            let mut pass=encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label:Some("Native Metal drawable"),
                color_attachments:&[Some(wgpu::RenderPassColorAttachment {
                    view:&view,resolve_target:None,
                    ops:wgpu::Operations {
                        load:wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store:wgpu::StoreOp::Store,
                    },
                    depth_slice:None,
                })],
                depth_stencil_attachment:None,
                timestamp_writes:None,occlusion_query_set:None,
                multiview_mask:None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0,&self.binding,&[]);
            pass.draw(0..3,0..1);
        }
        self.queue.submit(Some(encoder.finish()));
        frame.present();
        true
    }
}
impl NativeScene {
    fn frame(&mut self,seconds:f32) -> bool {
        let dt=seconds.clamp(0.0,0.1);
        let combined=self.touch.merge(&self.physical);
        let settings=PadSettings::default();
        for (button,down) in self.edges.update(&combined,settings.trigger_threshold) {
            if down {
                if button==Button::LeftBumper { self.hotbar=gamepad::hotbar_step(self.hotbar,false); }
                if button==Button::RightBumper { self.hotbar=gamepad::hotbar_step(self.hotbar,true); }
                self.last_action=gamepad::ACTIONS.iter().find(|(_,b)| *b==Some(button))
                    .map(|(action,_)| *action);
            }
        }
        let (dyaw,dpitch)=gamepad::look_delta(combined.right,&settings,dt,false);
        self.yaw+=dyaw;self.pitch=(self.pitch+dpitch).clamp(-90.0,90.0);
        if let Some(m)=gamepad::move_vector(combined.left,settings.move_deadzone) {
            self.preview_x+=m[0]*dt*5.0;
            self.preview_z+=m[1]*dt*5.0;
        }
        self.carry+=dt;
        while self.carry>=0.05 {
            self.ticks+=1;
            self.carry-=0.05;
        }
        if let Some(metal)=self.metal.as_mut(){
            metal.draw(dt,self.preview_x,self.preview_z,self.yaw,self.pitch)
        } else { false }
    }
}
/// 0: success; nonzero: no UIKit view / no available Metal device / error.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_metal_open(view: *mut c_void,width:u32,height:u32)->i32 {
    let Ok(mut state)=scene().lock() else {return 3};
    state.metal.take(); // Always tear down previous surface first.
    match MetalSurface::new(view,width,height) {
        Ok(surface)=>{state.metal=Some(surface);0}
        Err(error)=>{eprintln!("Horizon iOS Metal: {error}");2}
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_metal_resize(width:u32,height:u32) {
    if let Ok(mut s)=scene().lock() {
        if let Some(m)=s.metal.as_mut() {m.resize(width,height);}
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_metal_close() {
    if let Ok(mut s)=scene().lock() {
        s.metal=None;s.touch=PadState::default();s.physical=PadState::default();
        s.edges=Edges::default();
    }
}
/// 0 = virtual iOS touch controls; 1 = Apple's GameController hardware.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_pad_snapshot(
    source:u32,buttons:u32,left_x:f32,left_y:f32,right_x:f32,right_y:f32,lt:f32,rt:f32
) {
    if let Ok(mut s)=scene().lock() {
        let value=PadState{
            buttons:buttons & 0xffff,
            left:[left_x.clamp(-1.0,1.0),left_y.clamp(-1.0,1.0)],
            right:[right_x.clamp(-1.0,1.0),right_y.clamp(-1.0,1.0)],
            triggers:[lt.clamp(0.0,1.0),rt.clamp(0.0,1.0)],
        };
        match source {0=>s.touch=value,1=>s.physical=value,_=>{}}
    }
}
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_metal_frame(dt:f32)->bool {
    scene().lock().is_ok_and(|mut s|s.frame(dt))
}
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_preview_ticks()->u64 {
    scene().lock().map_or(0,|s|s.ticks)
}
