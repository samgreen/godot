#include "rasterizer_scene_metal.h"

#include "servers/visual/visual_server_raster.h"
#include "rasterizer_canvas_metal.h"

void RasterizerSceneMetal::initialize() {
    // Initialize the scene shader
    // Initialize the two sided shader
    // Initialize the world coord shader
    // Initialize the world coord two sided shader
    // Initialize the overdraw shader

    // Set Up uniform buffers

    // Find a good number for max elements in our render list
    render_list.max_elements = GLOBAL_DEF_RST("rendering/limits/rendering/max_renderable_elements", (int)RenderList::DEFAULT_MAX_ELEMENTS);
	if (render_list.max_elements > 1000000)
		render_list.max_elements = 1000000;
	if (render_list.max_elements < 1024)
		render_list.max_elements = 1024;

    // Set Up quad buffers

    // Set Up cube textures

    // Set up lights

    // Set up reflections

    // Skip immediate mode?

    // Init default shaders
    // state.resolve_shader.init();
    // state.ssr_shader.init();
    // state.effect_blur_shader.init();
    // state.sss_shader.init();
    // state.ssao_minify_shader.init();
    // state.ssao_shader.init();
    // state.ssao_blur_shader.init();
    // state.exposure_shader.init();
    // state.tonemap_shader.init();
}

void RasterizerSceneMetal::iteration() {

	// shadow_filter_mode = ShadowFilterMode(int(GLOBAL_GET("rendering/quality/shadows/filter_mode")));
	// subsurface_scatter_follow_surface = GLOBAL_GET("rendering/quality/subsurface_scattering/follow_surface");
	// subsurface_scatter_weight_samples = GLOBAL_GET("rendering/quality/subsurface_scattering/weight_samples");
	// subsurface_scatter_quality = SubSurfaceScatterQuality(int(GLOBAL_GET("rendering/quality/subsurface_scattering/quality")));
	// subsurface_scatter_size = GLOBAL_GET("rendering/quality/subsurface_scattering/scale");

	// state.scene_shader.set_conditional(SceneShaderGLES3::VCT_QUALITY_HIGH, GLOBAL_GET("rendering/quality/voxel_cone_tracing/high_quality"));
}

void RasterizerSceneMetal::finalize() {

}

RasterizerSceneMetal::RasterizerSceneMetal() {

}

RasterizerSceneMetal::~RasterizerSceneMetal() {

}