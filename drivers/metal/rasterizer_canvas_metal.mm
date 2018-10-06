
#include "rasterizer_canvas_metal.h"

#include "core/os/os.h"
#include "core/project_settings.h"
// rasterizer metal scene?
#include "servers/visual/visual_server_raster.h"

void RasterizerCanvasMetal::initialize() {
    device = MTLCreateSystemDefaultDevice();
    id<MTLLibrary> defaultLibrary = [device newDefaultLibrary];
    static const int kQuadBufferLength = 8;
    const float qv[kQuadBufferLength] = {
        0, 0,
        0, 1,
        1, 1,
        1, 0
    };
    data.canvas_quad_buffer = [device newBufferWithLength:kQuadBufferLength
                                                  options:MTLStorageModeShared];
    memcpy(data.canvas_quad_buffer, &qv, kQuadBufferLength);

    command_queue = [device newCommandQueue];
}

void RasterizerCanvasMetal::finalize() {
    
}

RasterizerCanvasMetal::RasterizerCanvasMetal() {

}

void RasterizerCanvasMetal::canvas_render_items(Item *p_item_list, int p_z, const Color &p_modulate, Light *p_light, const Transform2D &p_transform) {

}