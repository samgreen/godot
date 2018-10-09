#ifndef RASTERIZERSTOREMETAL_H
#define RASTERIZERSTOREMETAL_H

#include "core/self_list.h"
#include "servers/visual/rasterizer.h"
#include "servers/visual/shader_language.h"
#import <Metal/Metal.h>
#import <simd/simd.h>

class RasterizerCanvasMetal;
class RasterizerSceneMetal;

class RasterizerStorageMetal : public RasterizerStorage {
public:
	RasterizerCanvasMetal *canvas;
	RasterizerSceneMetal *scene;

	enum RenderArchitecture {
		RENDER_ARCH_MOBILE,
		RENDER_ARCH_DESKTOP,
	};

	struct Config {
		bool shrink_textures_x2;
		bool keep_original_textures;
		bool use_anisotropic_filter;
		bool generate_wireframes;
		bool hdr_supported;

		int max_texture_units;
		int max_texture_size;
	} config;

	mutable struct Shaders {

	} shaders;

	struct Resources {
		// 2D Textures
		// 3D Textures
		// Quads
		// Transform Feedback
	} resources;

	struct Info {

		uint64_t texture_mem;
		uint64_t vertex_mem;

		struct Render {
			uint32_t object_count;
			uint32_t draw_call_count;
			uint32_t material_switch_count;
			uint32_t surface_switch_count;
			uint32_t shader_rebind_count;
			uint32_t vertices_count;

			void reset() {
				object_count = 0;
				draw_call_count = 0;
				material_switch_count = 0;
				surface_switch_count = 0;
				shader_rebind_count = 0;
				vertices_count = 0;
			}
		} render, render_final, snap;

		Info() {

			texture_mem = 0;
			vertex_mem = 0;
			render.reset();
			render_final.reset();
		}

	} info;

	struct Instantiable : public RID_Data {

		SelfList<RasterizerScene::InstanceBase>::List instance_list;

		_FORCE_INLINE_ void instance_change_notify() {

			SelfList<RasterizerScene::InstanceBase> *instances = instance_list.first();
			while (instances) {

				instances->self()->base_changed();
				instances = instances->next();
			}
		}

		_FORCE_INLINE_ void instance_material_change_notify() {

			SelfList<RasterizerScene::InstanceBase> *instances = instance_list.first();
			while (instances) {

				instances->self()->base_material_changed();
				instances = instances->next();
			}
		}

		_FORCE_INLINE_ void instance_remove_deps() {
			SelfList<RasterizerScene::InstanceBase> *instances = instance_list.first();
			while (instances) {

				SelfList<RasterizerScene::InstanceBase> *next = instances->next();
				instances->self()->base_removed();
				instances = next;
			}
		}

		Instantiable() {}
		virtual ~Instantiable() {
		}
	};

	struct GeometryOwner : public Instantiable {

		virtual ~GeometryOwner() {}
	};

	struct Geometry : Instantiable {

		enum Type {
			GEOMETRY_INVALID,
			GEOMETRY_SURFACE,
			GEOMETRY_IMMEDIATE,
			GEOMETRY_MULTISURFACE,
		};

		Type type;
		RID material;
		uint64_t last_pass;
		uint32_t index;

		virtual void material_changed_notify() {}

		Geometry() {
			last_pass = 0;
			index = 0;
		}
	};

	// Light -> Instantiable
	// ReflectionProbe -> Instantiable
	// GIProbe -> Instantiable
	// LightmapCapture -> Instantiable

	// Surface -> Geometry
	// Immediate -> Geometry
	// Mesh -> GeometryOwner
	// MultiMesh -> GeometryOwner
	// Particles -> GeometryOwner

	// Texture -> RID_Data
	struct Texture : public RID_Data {
		Texture *proxy;
		Set<Texture *> proxy_owners;

		String path;
		uint32_t flags;
		int width, height, depth;
		Image::Format format;
		VS::TextureType type;
		MTLTextureType target_type;
		bool compressed;
		bool ignore_mipmaps;
		int mipmaps;
		bool active;
		bool redraw_if_visible;

		id<MTLTexture> metal_texture;

		Texture() {
			proxy = NULL;
			flags = width = depth = height = 0;
			compressed = false;
			ignore_mipmaps = false;
			mipmaps = 0;
			active = false;
			redraw_if_visible = false;
		}

		~Texture() {
		}
	};

	mutable RID_Owner<Texture> texture_owner;

	virtual RID texture_create();
	virtual void texture_allocate(RID p_texture, int p_width, int p_height, int p_depth_3d, Image::Format p_format, VS::TextureType p_type, uint32_t p_flags = VS::TEXTURE_FLAGS_DEFAULT);

	virtual void texture_set_data(RID p_texture, const Ref<Image> &p_image, int p_layer = 0);
	virtual void texture_set_data_partial(RID p_texture, const Ref<Image> &p_image, int src_x, int src_y, int src_w, int src_h, int dst_x, int dst_y, int p_dst_mip, int p_layer = 0);
	virtual Ref<Image> texture_get_data(RID p_texture, int p_layer = 0) const;

	virtual void texture_set_flags(RID p_texture, uint32_t p_flags);
	virtual uint32_t texture_get_flags(RID p_texture) const;

	virtual Image::Format texture_get_format(RID p_texture) const;
	virtual VS::TextureType texture_get_type(RID p_texture) const;
	virtual uint32_t texture_get_texid(RID p_texture) const;
	virtual uint32_t texture_get_width(RID p_texture) const;
	virtual uint32_t texture_get_height(RID p_texture) const;
	virtual uint32_t texture_get_depth(RID p_texture) const;
	virtual void texture_set_size_override(RID p_texture, int p_width, int p_height, int p_depth);

	virtual void texture_set_path(RID p_texture, const String &p_path);
	virtual String texture_get_path(RID p_texture) const;

	virtual void texture_debug_usage(List<VS::TextureInfo> *r_info);

	virtual void texture_set_shrink_all_x2_on_set_data(bool p_enable);
	virtual void textures_keep_original(bool p_enable);
	virtual RID texture_create_radiance_cubemap(RID p_source, int p_resolution = -1) const;

	virtual void texture_set_detect_3d_callback(RID p_texture, VisualServer::TextureDetectCallback p_callback, void *p_userdata);
	virtual void texture_set_detect_srgb_callback(RID p_texture, VisualServer::TextureDetectCallback p_callback, void *p_userdata);
	virtual void texture_set_detect_normal_callback(RID p_texture, VisualServer::TextureDetectCallback p_callback, void *p_userdata);

	virtual void texture_set_proxy(RID p_texture, RID p_proxy);
	virtual void texture_set_force_redraw_if_visible(RID p_texture, bool p_enable);

	// Sky -> RID_Data

	// Shader -> RID_Data
	struct Material;
	struct Shader : public RID_Data {

		RID self;

		bool valid;
		String path;

		VS::ShaderMode mode;
        id<MTLFunction> shader;
		String code;
		SelfList<Material>::List materials;

        Map<StringName, ShaderLanguage::ShaderNode::Uniform> uniforms;
		Vector<uint32_t> ubo_offsets;
		uint32_t ubo_size;

		uint32_t texture_count;

		uint32_t custom_code_id;
		uint32_t version;

		SelfList<Shader> dirty_list;

		Map<StringName, RID> default_textures;

		Vector<ShaderLanguage::DataType> texture_types;
		Vector<ShaderLanguage::ShaderNode::Uniform::Hint> texture_hints;

		bool uses_vertex_time;
		bool uses_fragment_time;

		struct CanvasItem {

		} canvas_item;

		struct Spatial {

		} spatial;

		struct Particles {

		} particles;

		Shader() :
				dirty_list(this) {

			shader = nil;
			ubo_size = 0;
			valid = false;
			custom_code_id = 0;
			version = 1;
		}
	};

    mutable RID_Owner<Shader> shader_owner;
    // mutable SelfList<Shader>::List _shader_dirty_list;

    virtual RID shader_create();

    virtual void shader_set_code(RID p_shader, const String &p_code);
	virtual String shader_get_code(RID p_shader) const;

	// Material -> RID_Data
	// Skeleton -> RID_Data
	// GIProbeData -> RID_Data
	// RenderTarget -> RID_Data
	// CanvasLightShadow -> RID_Data
	// CanvasOccluder -> RID_Data

	// Frame

	RasterizerStorageMetal();
};

#endif