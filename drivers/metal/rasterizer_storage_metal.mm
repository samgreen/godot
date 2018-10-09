#include "rasterizer_storage_metal.h"
#include "core/engine.h"
#include "core/project_settings.h"
#include "rasterizer_canvas_metal.h"

RID RasterizerStorageMetal::texture_create() {

	Texture *texture = memnew(Texture);
	ERR_FAIL_COND_V(!texture, RID());
	// glGenTextures(1, &texture->tex_id);
	texture->active = false;
	return texture_owner.make_rid(texture);
}

void RasterizerStorageMetal::texture_allocate(RID p_texture, int p_width, int p_height, int p_depth_3d, Image::Format p_format, VisualServer::TextureType p_type, uint32_t p_flags) {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);
	texture->width = p_width;
	texture->height = p_height;
	texture->depth = p_depth_3d;
	texture->format = p_format;
	texture->type = p_type;
	texture->flags = p_flags;

	switch (texture->type) {
		case VS::TEXTURE_TYPE_2D: {
			texture->target_type = MTLTextureType2D;
		} break;
		case VS::TEXTURE_TYPE_CUBEMAP: {
			texture->target_type = MTLTextureType2D;
		} break;
		case VS::TEXTURE_TYPE_2D_ARRAY: {
			texture->target_type = MTLTextureType2DArray;
		} break;
		case VS::TEXTURE_TYPE_3D: {
			texture->target_type = MTLTextureType3D;
		} break;
	}

    texture->mipmaps = 1;
	// TODO: Add extra allocation handling for cubemap and 2D array textures

	texture->active = true;
}

void RasterizerStorageMetal::texture_set_data(RID p_texture, const Ref<Image> &p_image, int p_layer) {

	ERR_FAIL_COND(p_image.is_null());

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);
	ERR_FAIL_COND(!texture->active);
	ERR_FAIL_COND(texture->format != p_image->get_format());

	// texture->ignore_mipmaps = (compressed && !img->has_mipmaps());

    bool generate_mip_maps = false;
    if ((texture->flags & VS::TEXTURE_FLAG_MIPMAPS) && !texture->ignore_mipmaps) {
		generate_mip_maps = true;
	} else {
        generate_mip_maps = (texture->flags & VS::TEXTURE_FLAG_FILTER);
	}

	// TODO: Create a helper to convert ImageFormat to Metal pixel formats
	MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
																								 width:texture->width
																								height:texture->height
																							 mipmapped:generate_mip_maps];
	textureDescriptor.pixelFormat = MTLPixelFormatBGRA8Unorm;
	textureDescriptor.width = texture->width;
	textureDescriptor.height = texture->height;

	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	texture->metal_texture = [device newTextureWithDescriptor:textureDescriptor];

    // TODO: Create MTLSamplerDescriptor to handle filtering, anistropy, mips
}

void RasterizerStorageMetal::texture_set_data_partial(RID p_texture, const Ref<Image> &p_image, int src_x, int src_y, int src_w, int src_h, int dst_x, int dst_y, int p_dst_mip, int p_layer) {

	Texture *texture = texture_owner.get(p_texture);

	ERR_FAIL_COND(!texture);
	ERR_FAIL_COND(!texture->active);
	ERR_FAIL_COND(texture->format != p_image->get_format());
	ERR_FAIL_COND(p_image.is_null());
	ERR_FAIL_COND(src_w <= 0 || src_h <= 0);
	ERR_FAIL_COND(src_x < 0 || src_y < 0 || src_x + src_w > p_image->get_width() || src_y + src_h > p_image->get_height());
	ERR_FAIL_COND(p_dst_mip < 0 || p_dst_mip >= texture->mipmaps);

	// GLenum type;
	// GLenum format;
	// GLenum internal_format;
	// bool compressed;
	// bool srgb;

	// // Because OpenGL wants data as a dense array, we have to extract the sub-image if the source rect isn't the full image
	// Ref<Image> p_sub_img = p_image;
	// if (src_x > 0 || src_y > 0 || src_w != p_image->get_width() || src_h != p_image->get_height()) {
	// 	p_sub_img = p_image->get_rect(Rect2(src_x, src_y, src_w, src_h));
	// }

	// Image::Format real_format;
	// Ref<Image> img = _get_gl_image_and_format(p_sub_img, p_sub_img->get_format(), texture->flags, real_format, format, internal_format, type, compressed, srgb);

	// GLenum blit_target;

	// switch (texture->type) {
	// 	case VS::TEXTURE_TYPE_2D: {
	// 		blit_target = GL_TEXTURE_2D;
	// 	} break;
	// 	case VS::TEXTURE_TYPE_CUBEMAP: {
	// 		ERR_FAIL_INDEX(p_layer, 6);
	// 		blit_target = _cube_side_enum[p_layer];
	// 	} break;
	// 	case VS::TEXTURE_TYPE_2D_ARRAY: {
	// 		blit_target = GL_TEXTURE_2D_ARRAY;
	// 	} break;
	// 	case VS::TEXTURE_TYPE_3D: {
	// 		blit_target = GL_TEXTURE_3D;
	// 	} break;
	// }

	// PoolVector<uint8_t>::Read read = img->get_data().read();

	// glActiveTexture(GL_TEXTURE0);
	// glBindTexture(texture->target, texture->tex_id);

	// int src_data_size = img->get_data().size();
	// int src_ofs = 0;

	if (texture->type == VS::TEXTURE_TYPE_2D || texture->type == VS::TEXTURE_TYPE_CUBEMAP) {
		if (texture->compressed) {
			// glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
			// glCompressedTexSubImage2D(blit_target, p_dst_mip, dst_x, dst_y, src_w, src_h, internal_format, src_data_size, &read[src_ofs]);

		} else {
			// glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
			// // `format` has to match the internal_format used when the texture was created
			// glTexSubImage2D(blit_target, p_dst_mip, dst_x, dst_y, src_w, src_h, format, type, &read[src_ofs]);
		}
	} else {
		if (texture->compressed) {
			// glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
			// glCompressedTexSubImage3D(blit_target, p_dst_mip, dst_x, dst_y, p_layer, src_w, src_h, 1, format, src_data_size, &read[src_ofs]);
		} else {
			// glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
			// // `format` has to match the internal_format used when the texture was created
			// glTexSubImage3D(blit_target, p_dst_mip, dst_x, dst_y, p_layer, src_w, src_h, 1, format, type, &read[src_ofs]);
		}
	}

	if (texture->flags & VS::TEXTURE_FLAG_FILTER) {

		// glTexParameteri(texture->target, GL_TEXTURE_MAG_FILTER, GL_LINEAR); // Linear Filtering

	} else {

		// glTexParameteri(texture->target, GL_TEXTURE_MAG_FILTER, GL_NEAREST); // raw Filtering
	}
}

Ref<Image> RasterizerStorageMetal::texture_get_data(RID p_texture, int p_layer) const {

	Texture *texture = texture_owner.get(p_texture);

	ERR_FAIL_COND_V(!texture, Ref<Image>());
	ERR_FAIL_COND_V(!texture->active, Ref<Image>());

	// if (texture->type == VS::TEXTURE_TYPE_CUBEMAP && p_layer < 6 && !texture->images[p_layer].is_null()) {
	// 	return texture->images[p_layer];
	// }

	ERR_EXPLAIN("Sorry, It's not possible to obtain images back in Metal.");
	ERR_FAIL_V(Ref<Image>());
}

void RasterizerStorageMetal::texture_set_flags(RID p_texture, uint32_t p_flags) {

    Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);

    bool had_mipmaps = texture->flags & VS::TEXTURE_FLAG_MIPMAPS;
    texture->flags = p_flags;

	// glActiveTexture(GL_TEXTURE0);
	// glBindTexture(texture->target, texture->tex_id);

	// if (((texture->flags & VS::TEXTURE_FLAG_REPEAT) || (texture->flags & VS::TEXTURE_FLAG_MIRRORED_REPEAT)) && texture->target != GL_TEXTURE_CUBE_MAP) {

	// 	if (texture->flags & VS::TEXTURE_FLAG_MIRRORED_REPEAT) {
	// 		// glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_MIRRORED_REPEAT);
	// 		// glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_MIRRORED_REPEAT);
	// 	} else {
	// 		// glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
	// 		// glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
	// 	}
	// } else {
	// 	// glTexParameterf(texture->target, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	// 	// glTexParameterf(texture->target, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	// }

    if (config.use_anisotropic_filter) {
		if (texture->flags & VS::TEXTURE_FLAG_ANISOTROPIC_FILTER) {
			// glTexParameterf(texture->target, _GL_TEXTURE_MAX_ANISOTROPY_EXT, config.anisotropic_level);
		} else {
			// glTexParameterf(texture->target, _GL_TEXTURE_MAX_ANISOTROPY_EXT, 1);
		}
	}

    if ((texture->flags & VS::TEXTURE_FLAG_MIPMAPS) && !texture->ignore_mipmaps) {
		if (!had_mipmaps && texture->mipmaps == 1) {
			// glGenerateMipmap(texture->target);
		}
		// glTexParameteri(texture->target, GL_TEXTURE_MIN_FILTER, config.use_fast_texture_filter ? GL_LINEAR_MIPMAP_NEAREST : GL_LINEAR_MIPMAP_LINEAR);

	} else {
		if (texture->flags & VS::TEXTURE_FLAG_FILTER) {
			// glTexParameteri(texture->target, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		} else {
			// glTexParameteri(texture->target, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		}
	}

    if (texture->flags & VS::TEXTURE_FLAG_FILTER) {
		// glTexParameteri(texture->target, GL_TEXTURE_MAG_FILTER, GL_LINEAR); // Linear Filtering
	} else {
		// glTexParameteri(texture->target, GL_TEXTURE_MAG_FILTER, GL_NEAREST); // raw Filtering
	}
}

uint32_t RasterizerStorageMetal::texture_get_flags(RID p_texture) const {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND_V(!texture, 0);
	return texture->flags;
}

Image::Format RasterizerStorageMetal::texture_get_format(RID p_texture) const {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND_V(!texture, Image::FORMAT_L8);
	return texture->format;
}

VisualServer::TextureType RasterizerStorageMetal::texture_get_type(RID p_texture) const {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND_V(!texture, VS::TEXTURE_TYPE_2D);
	return texture->type;
}

uint32_t RasterizerStorageMetal::texture_get_texid(RID p_texture) const {

    // TODO: Implement this
    return -1;
	// Texture *texture = texture_owner.get(p_texture);
	// ERR_FAIL_COND_V(!texture, 0);
	// return texture->tex_id;
}
uint32_t RasterizerStorageMetal::texture_get_width(RID p_texture) const {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND_V(!texture, 0);
	return texture->width;
}
uint32_t RasterizerStorageMetal::texture_get_height(RID p_texture) const {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND_V(!texture, 0);
	return texture->height;
}

uint32_t RasterizerStorageMetal::texture_get_depth(RID p_texture) const {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND_V(!texture, 0);
	return texture->depth;
}

void RasterizerStorageMetal::texture_set_size_override(RID p_texture, int p_width, int p_height, int p_depth) {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);

	ERR_FAIL_COND(p_width <= 0 || p_width > 16384);
	ERR_FAIL_COND(p_height <= 0 || p_height > 16384);
	//real texture size is in alloc width and height
	texture->width = p_width;
	texture->height = p_height;
}

void RasterizerStorageMetal::texture_set_path(RID p_texture, const String &p_path) {
	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);
	texture->path = p_path;
}

String RasterizerStorageMetal::texture_get_path(RID p_texture) const {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND_V(!texture, String());
	return texture->path;
}

void RasterizerStorageMetal::texture_debug_usage(List<VS::TextureInfo> *r_info) {

	List<RID> textures;
	texture_owner.get_owned_list(&textures);

	for (List<RID>::Element *E = textures.front(); E; E = E->next()) {

		Texture *t = texture_owner.get(E->get());
		if (!t)
			continue;
		VS::TextureInfo tinfo;
		tinfo.path = t->path;
		tinfo.format = t->format;
		tinfo.width = t->width;
		tinfo.height = t->width;
		tinfo.depth = 0;
		r_info->push_back(tinfo);
	}
}

void RasterizerStorageMetal::texture_set_shrink_all_x2_on_set_data(bool p_enable) {

	config.shrink_textures_x2 = p_enable;
}

void RasterizerStorageMetal::textures_keep_original(bool p_enable) {

	config.keep_original_textures = p_enable;
}

void RasterizerStorageMetal::texture_set_proxy(RID p_texture, RID p_proxy) {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);

	if (texture->proxy) {
		texture->proxy->proxy_owners.erase(texture);
		texture->proxy = NULL;
	}

	if (p_proxy.is_valid()) {
		Texture *proxy = texture_owner.get(p_proxy);
		ERR_FAIL_COND(!proxy);
		ERR_FAIL_COND(proxy == texture);
		proxy->proxy_owners.insert(texture);
		texture->proxy = proxy;
	}
}

void RasterizerStorageMetal::texture_set_force_redraw_if_visible(RID p_texture, bool p_enable) {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);
	texture->redraw_if_visible = p_enable;
}

void RasterizerStorageMetal::texture_set_detect_3d_callback(RID p_texture, VisualServer::TextureDetectCallback p_callback, void *p_userdata) {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);
	// texture->detect_3d = p_callback;
	// texture->detect_3d_ud = p_userdata;
}

void RasterizerStorageMetal::texture_set_detect_srgb_callback(RID p_texture, VisualServer::TextureDetectCallback p_callback, void *p_userdata) {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);
	// texture->detect_srgb = p_callback;
	// texture->detect_srgb_ud = p_userdata;
}

void RasterizerStorageMetal::texture_set_detect_normal_callback(RID p_texture, VisualServer::TextureDetectCallback p_callback, void *p_userdata) {

	Texture *texture = texture_owner.get(p_texture);
	ERR_FAIL_COND(!texture);
	// texture->detect_normal = p_callback;
	// texture->detect_normal_ud = p_userdata;
}

RID RasterizerStorageMetal::texture_create_radiance_cubemap(RID p_source, int p_resolution) const {
	Texture *texture = texture_owner.get(p_source);
	ERR_FAIL_COND_V(!texture, RID());
	ERR_FAIL_COND_V(texture->type != VS::TEXTURE_TYPE_CUBEMAP, RID());
    return RID();
}