#ifndef RASTERIZERSCENEMETAL_H
#define RASTERIZERSCENEMETAL_H

#include "rasterizer_storage_metal.h"

class RasterizerSceneMetal : public RasterizerScene {
public:

    struct State {

    } state;

    struct DirectionalShadow {

    } directional_shadow;

    // Environment 

    struct Environment : public RID_Data {

    };
    RID_Owner<Environment> environment_owner;

    // Light Instance
    struct LightInstance : public RID_Data {
        
    };
    mutable RID_Owner<LightInstance> light_instance_owner;

    // Probe Instance
    struct GIProbeInstance : public RID_Data {

    };
    mutable RID_Owner<GIProbeInstance> gi_probe_instance_owner;

    // Render List
    struct RenderList {
        enum {
			DEFAULT_MAX_ELEMENTS = 65536,
        };
        
        int max_elements;

        struct Element {

        };
    };
    RenderList render_list;

	void iteration();
	void initialize();
	void finalize();

	RasterizerSceneMetal();
	~RasterizerSceneMetal();
};

#endif