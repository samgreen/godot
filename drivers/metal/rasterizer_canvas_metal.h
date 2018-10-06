#ifndef RASTERIZERCANVASMETAL_H
#define RASTERIZERCANVASMETAL_H

#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#include "rasterizer_storage_metal.h"
#include "servers/visual/rasterizer.h"

class RasterizerCanvasMetal : public RasterizerCanvas {
public:

    struct Data {
        id<MTLBuffer> canvas_quad_buffer;
        id<MTLBuffer> polygon_buffer;
        id<MTLBuffer> particle_quad_buffer;
    } data;

    struct State {
        id<MTLCommandQueue> command_queue;
    } state;

	virtual RID light_internal_create();
	virtual void light_internal_update(RID p_rid, Light *p_light);
	virtual void light_internal_free(RID p_rid);

	virtual void canvas_begin();
	virtual void canvas_end();

    virtual void canvas_render_items(Item *p_item_list, int p_z, const Color &p_modulate, Light *p_light, const Transform2D &p_transform);
	virtual void canvas_debug_viewport_shadows(Light *p_lights_with_shadow);
    virtual void canvas_light_shadow_buffer_update(RID p_buffer, const Transform2D &p_light_xform, int p_light_mask, float p_near, float p_far, LightOccluderInstance *p_occluders, CameraMatrix *p_xform_cache);

	virtual void reset_canvas();

    virtual void draw_window_margins(int *black_margin, RID *black_image);

    void initialize();
    void finalize();

    RasterizerCanvasMetal();
private:
    id<MTLDevice> device;
};

#endif