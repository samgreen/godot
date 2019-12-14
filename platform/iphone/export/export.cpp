/*************************************************************************/
/*  export.cpp                                                           */
/*************************************************************************/
/*                       This file is part of:                           */
/*                           GODOT ENGINE                                */
/*                      https://godotengine.org                          */
/*************************************************************************/
/* Copyright (c) 2007-2019 Juan Linietsky, Ariel Manzur.                 */
/* Copyright (c) 2014-2019 Godot Engine contributors (cf. AUTHORS.md)    */
/*                                                                       */
/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the       */
/* "Software"), to deal in the Software without restriction, including   */
/* without limitation the rights to use, copy, modify, merge, publish,   */
/* distribute, sublicense, and/or sell copies of the Software, and to    */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions:                                             */
/*                                                                       */
/* The above copyright notice and this permission notice shall be        */
/* included in all copies or substantial portions of the Software.       */
/*                                                                       */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,       */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF    */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.*/
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY  */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,  */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE     */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                */
/*************************************************************************/

#include "export.h"
#include "core/io/marshalls.h"
#include "core/io/resource_saver.h"
#include "core/io/zip_io.h"
#include "core/os/file_access.h"
#include "core/os/os.h"
#include "core/project_settings.h"
#include "core/version.h"
#include "editor/editor_export.h"
#include "editor/editor_node.h"
#include "editor/editor_settings.h"
#include "platform/iphone/logo.gen.h"
#include "string.h"

#include <sys/stat.h>

class EditorExportPlatformIOS : public EditorExportPlatform {

	GDCLASS(EditorExportPlatformIOS, EditorExportPlatform);

	int version_code;

	Ref<ImageTexture> logo;

	typedef Error (*FileHandler)(String p_file, void *p_userdata);
	static Error _walk_dir_recursive(DirAccess *p_da, FileHandler p_handler, void *p_userdata);
	static Error _codesign(String p_file, void *p_userdata);

	struct IOSConfigData {
		String pkg_name;
		String binary_name;
		String plist_content;
		String architectures;
		String linker_flags;
		String cpp_code;
		String modules_buildfile;
		String modules_fileref;
		String modules_buildphase;
		String modules_buildgrp;
	};

	struct ExportArchitecture {
		String name;
		bool is_default;

		ExportArchitecture() :
				name(""),
				is_default(false) {
		}

		ExportArchitecture(String p_name, bool p_is_default) {
			name = p_name;
			is_default = p_is_default;
		}
	};

	struct IOSExportAsset {
		String exported_path;
		bool is_framework; // framework is anything linked to the binary, otherwise it's a resource
	};

	String _get_additional_plist_content();
	String _get_linker_flags();
	String _get_cpp_code();
	void _fix_project_file(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &pfile, const IOSConfigData &p_config, bool p_debug);
	void _fix_config_file(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &pfile, const IOSConfigData &p_config, bool p_debug);
	void _fix_plist_file(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &pfile, const IOSConfigData &p_config, bool p_debug);
	void _append_to_file(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &pfile, const IOSConfigData &p_config, bool p_debug);

	Error _export_icons(const Ref<EditorExportPreset> &p_preset, const String &p_iconset_dir);

	Vector<ExportArchitecture> _get_supported_architectures();
	Vector<String> _get_preset_architectures(const Ref<EditorExportPreset> &p_preset);

	void _add_assets_to_project(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &p_project_data, const Vector<IOSExportAsset> &p_additional_assets);
	Error _export_additional_assets(const String &p_out_dir, const Vector<String> &p_assets, bool p_is_framework, Vector<IOSExportAsset> &r_exported_assets);
	Error _export_additional_assets(const String &p_out_dir, const Vector<SharedObject> &p_libraries, Vector<IOSExportAsset> &r_exported_assets);

	String get_binary_path(const EditorExportPlatformIOS::IOSConfigData &p_config);

	bool is_package_name_valid(const String &p_package, String *r_error = NULL) const {

		String pname = p_package;

		if (pname.length() == 0) {
			if (r_error) {
				*r_error = TTR("Identifier is missing.");
			}
			return false;
		} else if (pname.length() < 2) {
			if (r_error) {
				*r_error = TTR("Identifier is too short. Must be at least 2 characters.");
			}
		} else if (pname.length() > 255) {
			if (r_error) {
				*r_error = TTR("Identifier is too long. Must be less than 255 characters.");
			}
		}

		int segments = 0;
		bool first = true;
		for (int i = 0; i < pname.length(); i++) {
			CharType c = pname[i];
			if (first && c == '.') {
				if (r_error) {
					*r_error = TTR("Identifier segments must be of non-zero length.");
				}
				return false;
			}
			if (c == '.') {
				segments++;
				first = true;
				continue;
			}
			if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) {
				if (r_error) {
					*r_error = vformat(TTR("The character '%s' is not allowed in Identifier."), String::chr(c));
				}
				return false;
			}
			if (first && (c >= '0' && c <= '9')) {
				if (r_error) {
					*r_error = TTR("A digit cannot be the first character in a Identifier segment.");
				}
				return false;
			}
			if (first && c == '-') {
				if (r_error) {
					*r_error = vformat(TTR("The character '%s' cannot be the first character in a Identifier segment."), String::chr(c));
				}
				return false;
			}
			first = false;
		}

		if (first) {
			if (r_error) {
				*r_error = TTR("Identifier segments must be of non-zero length.");
			}
			return false;
		}

		return true;
	}

protected:
	virtual void get_preset_features(const Ref<EditorExportPreset> &p_preset, List<String> *r_features);
	virtual void get_export_options(List<ExportOption> *r_options);

public:
	virtual String get_name() const { return "iOS"; }
	virtual String get_os_name() const { return "iOS"; }
	virtual Ref<Texture> get_logo() const { return logo; }

	virtual List<String> get_binary_extensions(const Ref<EditorExportPreset> &p_preset) const {
		List<String> list;
		list.push_back("ipa");
		return list;
	}
	virtual Error export_project(const Ref<EditorExportPreset> &p_preset, bool p_debug, const String &p_path, int p_flags = 0);
	virtual void add_module_code(const Ref<EditorExportPreset> &p_preset, IOSConfigData &p_config_data, const String &p_name, const String &p_fid, const String &p_gid);

	virtual bool can_export(const Ref<EditorExportPreset> &p_preset, String &r_error, bool &r_missing_templates) const;

	virtual void get_platform_features(List<String> *r_features) {

		r_features->push_back("mobile");
		r_features->push_back("iOS");
	}

	virtual void resolve_platform_feature_priorities(const Ref<EditorExportPreset> &p_preset, Set<String> &p_features) {
	}

	EditorExportPlatformIOS();
	~EditorExportPlatformIOS();
};

void EditorExportPlatformIOS::get_preset_features(const Ref<EditorExportPreset> &p_preset, List<String> *r_features) {

	String driver = ProjectSettings::get_singleton()->get("rendering/quality/driver/driver_name");
	if (driver == "GLES2") {
		r_features->push_back("etc");
	} else if (driver == "GLES3") {
		r_features->push_back("etc2");
		if (ProjectSettings::get_singleton()->get("rendering/quality/driver/fallback_to_gles2")) {
			r_features->push_back("etc");
		}
	}

	Vector<String> architectures = _get_preset_architectures(p_preset);
	for (int i = 0; i < architectures.size(); ++i) {
		r_features->push_back(architectures[i]);
	}
}

Vector<EditorExportPlatformIOS::ExportArchitecture> EditorExportPlatformIOS::_get_supported_architectures() {
	Vector<ExportArchitecture> archs;
	archs.push_back(ExportArchitecture("armv7", false)); // Disabled by default, not included in official templates.
	archs.push_back(ExportArchitecture("arm64", true));
	return archs;
}

void EditorExportPlatformIOS::get_export_options(List<ExportOption> *r_options) {

	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "custom_package/debug", PROPERTY_HINT_GLOBAL_FILE, "*.zip"), ""));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "custom_package/release", PROPERTY_HINT_GLOBAL_FILE, "*.zip"), ""));

	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/app_store_team_id", PROPERTY_HINT_PLACEHOLDER_TEXT, "ZXSYZ493U4"), ""));

	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/code_sign_identity_debug", PROPERTY_HINT_PLACEHOLDER_TEXT, "iPhone Developer"), "iPhone Developer"));
	r_options->push_back(ExportOption(PropertyInfo(Variant::INT, "application/export_method_debug", PROPERTY_HINT_ENUM, "App Store,Development,Ad-Hoc,Enterprise"), 1));

	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/code_sign_identity_release", PROPERTY_HINT_PLACEHOLDER_TEXT, "iPhone Distribution"), "iPhone Distribution"));
	r_options->push_back(ExportOption(PropertyInfo(Variant::INT, "application/export_method_release", PROPERTY_HINT_ENUM, "App Store,Development,Ad-Hoc,Enterprise"), 0));

	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/name", PROPERTY_HINT_PLACEHOLDER_TEXT, "Game Name"), ""));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/info"), "Made with Godot Engine"));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/identifier", PROPERTY_HINT_PLACEHOLDER_TEXT, "com.example.game"), ""));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/build_number"), "1"));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/version"), "1.0.0"));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/copyright"), ""));

	// These set the `SystemCapabilities` property of the Xcode project.
	// They *must* match the capabilities of your provisioning profile
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "capabilities/arkit"), false));
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "capabilities/camera"), false));
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "capabilities/in_app_purchases"), false));
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "capabilities/push_notifications"), false));

	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "user_data/accessible_from_files_app"), false));
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "user_data/accessible_from_itunes_sharing"), false));

	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "privacy/camera_usage_description", PROPERTY_HINT_PLACEHOLDER_TEXT, "Provide a message if you need to use the camera"), ""));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "privacy/microphone_usage_description", PROPERTY_HINT_PLACEHOLDER_TEXT, "Provide a message if you need to use the microphone"), ""));
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "privacy/photolibrary_usage_description", PROPERTY_HINT_PLACEHOLDER_TEXT, "Provide a message if you need access to the photo library"), ""));

	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "orientation/portrait"), true));
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "orientation/portrait_upside_down"), true));
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "orientation/landscape_left"), true));
	r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "orientation/landscape_right"), true));

	// We should be able to downsize and generate the remaining icons from this icon
	// TODO: Generate other icon sizes from this new export option
	r_options->push_back(ExportOption(PropertyInfo(Variant::STRING, "application/icon_1024x1024", PROPERTY_HINT_FILE, "*.png"), ""));

	// Add architectures to allow the user to select from armv7 (disabled by default) and arm64. This is the
	// place to add new architectures like arm64e
	Vector<ExportArchitecture> architectures = _get_supported_architectures();
	for (int i = 0; i < architectures.size(); ++i) {
		r_options->push_back(ExportOption(PropertyInfo(Variant::BOOL, "architectures/" + architectures[i].name), architectures[i].is_default));
	}
}

String make_xcconfig_setting(String key, Variant value) {
	return key + " = " + String(value) + ";\n";
}

String EditorExportPlatformIOS::get_binary_path(const EditorExportPlatformIOS::IOSConfigData &p_config) {
	return p_config.binary_name + "/" + p_config.binary_name;
}

void EditorExportPlatformIOS::_append_to_file(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &pfile, const IOSConfigData &p_config, bool p_debug) {
	// Load existing file contents to memory
	String str;
	str.parse_utf8((const char *)pfile.ptr(), pfile.size());

	// Create a new string to append to original values
	String strnew;
	strnew += make_xcconfig_setting("PRODUCT_BUNDLE_IDENTIFIER", p_preset->get("application/identifier"));
	strnew += make_xcconfig_setting("DEVELOPMENT_TEAM", p_preset->get("application/app_store_team_id"));
	
	// Pass build settings from Godot export options
	strnew += make_xcconfig_setting("ARCHS", p_config.architectures);
	strnew += make_xcconfig_setting("FRAMEWORK_SEARCH_PATHS", "$(inherited) " + p_config.binary_name);
	strnew += make_xcconfig_setting("OTHER_LDFLAGS", "$(inherited) $(GODOT_DEFAULT_LDFLAGS) " + p_config.linker_flags);

	// if enabled, add development (sandbox) APNS entitlements
	if ((bool)p_preset->get("capabilities/push_notifications")) {
		strnew += make_xcconfig_setting("CODE_SIGN_ENTITLEMENTS[config=Debug][sdk=iphoneos*]", get_binary_path(p_config) + ".entitlements");
	}

	// Add versions to xcconfig for use in build settings
	strnew += make_xcconfig_setting("GODOT_BUILD_NUMBER", p_preset->get("application/build_number"));
	strnew += make_xcconfig_setting("GODOT_VERSION_NAME", p_preset->get("application/version"));

	print_line("Appending values to godot.xcconfig: " + strnew);

	String strfile = str + strnew;
	CharString cs = strfile.utf8();
	pfile.resize(cs.size() - 1);
	for (int i = 0; i < cs.size() - 1; i++) {
		pfile.write[i] = cs[i];
	}
}

void EditorExportPlatformIOS::_fix_config_file(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &pfile, const IOSConfigData &p_config, bool p_debug) {
	static const String export_method_string[] = {
		"app-store",
		"development",
		"ad-hoc",
		"enterprise"
	};
	// Failsafe in case the user deleted these
	String debug_identity = p_preset->get("application/code_sign_identity_debug");
	if (debug_identity.length() == 0) {
		debug_identity = "iPhone Developer";
	}
	String release_identity = p_preset->get("application/code_sign_identity_release");
	if (release_identity.length() == 0) {
		release_identity = "iPhone Distribution";
	}
	String str;
	String strnew;
	str.parse_utf8((const char *)pfile.ptr(), pfile.size());
	Vector<String> lines = str.split("\n");
	for (int i = 0; i < lines.size(); i++) {
		if (lines[i].find("$binary") != -1) {
			strnew += lines[i].replace("$binary", p_config.binary_name) + "\n";
		} else if (lines[i].find("$modules_buildfile") != -1) {
			strnew += lines[i].replace("$modules_buildfile", p_config.modules_buildfile) + "\n";
		} else if (lines[i].find("$modules_fileref") != -1) {
			strnew += lines[i].replace("$modules_fileref", p_config.modules_fileref) + "\n";
		} else if (lines[i].find("$modules_buildphase") != -1) {
			strnew += lines[i].replace("$modules_buildphase", p_config.modules_buildphase) + "\n";
		} else if (lines[i].find("$modules_buildgrp") != -1) {
			strnew += lines[i].replace("$modules_buildgrp", p_config.modules_buildgrp) + "\n";
		} else if (lines[i].find("$name") != -1) {
			strnew += lines[i].replace("$name", p_config.pkg_name) + "\n";
		} else if (lines[i].find("$info") != -1) {
			strnew += lines[i].replace("$info", p_preset->get("application/info")) + "\n";
		} else if (lines[i].find("$identifier") != -1) {
			strnew += lines[i].replace("$identifier", p_preset->get("application/identifier")) + "\n";
		} else if (lines[i].find("$copyright") != -1) {
			strnew += lines[i].replace("$copyright", p_preset->get("application/copyright")) + "\n";
		} else if (lines[i].find("$export_method") != -1) {
			int export_method = p_preset->get(p_debug ? "application/export_method_debug" : "application/export_method_release");
			strnew += lines[i].replace("$export_method", export_method_string[export_method]) + "\n";
		} else if (lines[i].find("$code_sign_identity_debug") != -1) {
			strnew += lines[i].replace("$code_sign_identity_debug", debug_identity) + "\n";
		} else if (lines[i].find("$code_sign_identity_release") != -1) {
			strnew += lines[i].replace("$code_sign_identity_release", release_identity) + "\n";
		} else if (lines[i].find("$additional_plist_content") != -1) {
			strnew += lines[i].replace("$additional_plist_content", p_config.plist_content) + "\n";
		} else if (lines[i].find("$linker_flags") != -1) {
			strnew += lines[i].replace("$linker_flags", p_config.linker_flags) + "\n";
		} else if (lines[i].find("$cpp_code") != -1) {
			strnew += lines[i].replace("$cpp_code", p_config.cpp_code) + "\n";
		} else if (lines[i].find("$docs_in_place") != -1) {
			strnew += lines[i].replace("$docs_in_place", ((bool)p_preset->get("user_data/accessible_from_files_app")) ? "<true/>" : "<false/>") + "\n";
		} else if (lines[i].find("$docs_sharing") != -1) {
			strnew += lines[i].replace("$docs_sharing", ((bool)p_preset->get("user_data/accessible_from_itunes_sharing")) ? "<true/>" : "<false/>") + "\n";
		} else if (lines[i].find("$in_app_purchases") != -1) {
			bool is_on = p_preset->get("capabilities/in_app_purchases");
			strnew += lines[i].replace("$in_app_purchases", is_on ? "1" : "0") + "\n";
		} else if (lines[i].find("$push_notifications") != -1) {
			bool is_on = p_preset->get("capabilities/push_notifications");
			strnew += lines[i].replace("$push_notifications", is_on ? "1" : "0") + "\n";
		} else if (lines[i].find("$required_device_capabilities") != -1) {
			String capabilities;

			// I've removed armv7 as we can run on 64bit only devices
			// Note that capabilities listed here are requirements for the app to be installed.
			// They don't enable anything.

			if ((bool)p_preset->get("capabilities/arkit")) {
				capabilities += "<string>arkit</string>\n";
			}

			strnew += lines[i].replace("$required_device_capabilities", capabilities);
		} else if (lines[i].find("$interface_orientations") != -1) {
			String orientations;

			if ((bool)p_preset->get("orientation/portrait")) {
				orientations += "<string>UIInterfaceOrientationPortrait</string>\n";
			}
			if ((bool)p_preset->get("orientation/landscape_left")) {
				orientations += "<string>UIInterfaceOrientationLandscapeLeft</string>\n";
			}
			if ((bool)p_preset->get("orientation/landscape_right")) {
				orientations += "<string>UIInterfaceOrientationLandscapeRight</string>\n";
			}
			if ((bool)p_preset->get("orientation/portrait_upside_down")) {
				orientations += "<string>UIInterfaceOrientationPortraitUpsideDown</string>\n";
			}

			strnew += lines[i].replace("$interface_orientations", orientations);
		} else if (lines[i].find("$camera_usage_description") != -1) {
			String description = p_preset->get("privacy/camera_usage_description");
			strnew += lines[i].replace("$camera_usage_description", description) + "\n";
		} else if (lines[i].find("$microphone_usage_description") != -1) {
			String description = p_preset->get("privacy/microphone_usage_description");
			strnew += lines[i].replace("$microphone_usage_description", description) + "\n";
		} else if (lines[i].find("$photolibrary_usage_description") != -1) {
			String description = p_preset->get("privacy/photolibrary_usage_description");
			strnew += lines[i].replace("$photolibrary_usage_description", description) + "\n";
		} else {
			strnew += lines[i] + "\n";
		}
	}

	// Truncate the file and write appropriately
	CharString cs = strnew.utf8();
	pfile.resize(cs.size() - 1);
	for (int i = 0; i < cs.size() - 1; i++) {
		pfile.write[i] = cs[i];
	}
}

String EditorExportPlatformIOS::_get_additional_plist_content() {
	Vector<Ref<EditorExportPlugin> > export_plugins = EditorExport::get_singleton()->get_export_plugins();
	String result;
	for (int i = 0; i < export_plugins.size(); ++i) {
		result += export_plugins[i]->get_ios_plist_content();
	}
	return result;
}

String EditorExportPlatformIOS::_get_linker_flags() {
	Vector<Ref<EditorExportPlugin> > export_plugins = EditorExport::get_singleton()->get_export_plugins();
	String result;
	for (int i = 0; i < export_plugins.size(); ++i) {
		String flags = export_plugins[i]->get_ios_linker_flags();
		if (flags.length() == 0) continue;
		if (result.length() > 0) {
			result += ' ';
		}
		result += flags;
	}
	// the flags will be enclosed in quotes, so need to escape them
	return result.replace("\"", "\\\"");
}

String EditorExportPlatformIOS::_get_cpp_code() {
	Vector<Ref<EditorExportPlugin> > export_plugins = EditorExport::get_singleton()->get_export_plugins();
	String result;
	for (int i = 0; i < export_plugins.size(); ++i) {
		result += export_plugins[i]->get_ios_cpp_code();
	}
	return result;
}

struct IconInfo {
	const char *preset_key;
	const char *idiom;
	const char *export_name;
	const char *actual_size_side;
	const char *scale;
	const char *unscaled_size;
};

static const IconInfo icon_infos[] = {
	{ "application/icon_1024x1024", "ios-marketing", "Icon-1024.png", "1024", "1x", "1024x1024"}
};

Error EditorExportPlatformIOS::_export_icons(const Ref<EditorExportPreset> &p_preset, const String &p_iconset_dir) {
	String json_description = "{\"images\":[";
	String sizes;

	DirAccess *da = DirAccess::open(p_iconset_dir);
	ERR_FAIL_COND_V_MSG(!da, ERR_CANT_OPEN, "Cannot open directory '" + p_iconset_dir + "'.");

	for (uint64_t i = 0; i < (sizeof(icon_infos) / sizeof(icon_infos[0])); ++i) {
		IconInfo info = icon_infos[i];

		String icon_path = p_preset->get(info.preset_key);
		if (!p_preset->get(info.preset_key) || icon_path == "") {
			continue;
		}
		print_line("Found AppIcon at path: " + icon_path);

		Error err = da->copy(icon_path, p_iconset_dir + info.export_name);
		if (err) {
			memdelete(da);
			String err_str = String("Failed to export icon: ") + icon_path;
			ERR_PRINT(err_str.utf8().get_data());
			return err;
		}
		sizes += String(info.actual_size_side) + "\n";
		if (i > 0) {
			json_description += ",";
		}
		json_description += String("{");
		json_description += String("\"idiom\":") + "\"" + info.idiom + "\",";
		json_description += String("\"size\":") + "\"" + info.unscaled_size + "\",";
		json_description += String("\"scale\":") + "\"" + info.scale + "\",";
		json_description += String("\"filename\":") + "\"" + info.export_name + "\"";
		json_description += String("}");
	}
	json_description += "]}";
	memdelete(da);

	FileAccess *json_file = FileAccess::open(p_iconset_dir + "Contents.json", FileAccess::WRITE);
	ERR_FAIL_COND_V(!json_file, ERR_CANT_CREATE);
	CharString json_utf8 = json_description.utf8();
	json_file->store_buffer((const uint8_t *)json_utf8.get_data(), json_utf8.length());
	memdelete(json_file);

	FileAccess *sizes_file = FileAccess::open(p_iconset_dir + "sizes", FileAccess::WRITE);
	ERR_FAIL_COND_V(!sizes_file, ERR_CANT_CREATE);
	CharString sizes_utf8 = sizes.utf8();
	sizes_file->store_buffer((const uint8_t *)sizes_utf8.get_data(), sizes_utf8.length());
	memdelete(sizes_file);

	return OK;
}

Error EditorExportPlatformIOS::_walk_dir_recursive(DirAccess *p_da, FileHandler p_handler, void *p_userdata) {
	Vector<String> dirs;
	String path;
	String current_dir = p_da->get_current_dir();
	p_da->list_dir_begin();
	while ((path = p_da->get_next()).length() != 0) {
		if (p_da->current_is_dir()) {
			if (path != "." && path != "..") {
				dirs.push_back(path);
			}
		} else {
			Error err = p_handler(current_dir.plus_file(path), p_userdata);
			if (err) {
				p_da->list_dir_end();
				return err;
			}
		}
	}
	p_da->list_dir_end();

	for (int i = 0; i < dirs.size(); ++i) {
		String dir = dirs[i];
		p_da->change_dir(dir);
		Error err = _walk_dir_recursive(p_da, p_handler, p_userdata);
		p_da->change_dir("..");
		if (err) {
			return err;
		}
	}

	return OK;
}

struct CodesignData {
	const Ref<EditorExportPreset> &preset;
	bool debug;

	CodesignData(const Ref<EditorExportPreset> &p_preset, bool p_debug) :
			preset(p_preset),
			debug(p_debug) {
	}
};

Error EditorExportPlatformIOS::_codesign(String p_file, void *p_userdata) {
	if (p_file.ends_with(".dylib")) {
		CodesignData *data = (CodesignData *)p_userdata;
		print_line(String("Code Signing ") + p_file);
		List<String> codesign_args;
		codesign_args.push_back("-f");
		codesign_args.push_back("-s");
		codesign_args.push_back(data->preset->get(data->debug ? "application/code_sign_identity_debug" : "application/code_sign_identity_release"));
		codesign_args.push_back(p_file);
		return OS::get_singleton()->execute("codesign", codesign_args, true);
	}
	return OK;
}

struct PbxId {
private:
	static char _hex_char(uint8_t four_bits) {
		if (four_bits < 10) {
			return ('0' + four_bits);
		}
		return 'A' + (four_bits - 10);
	}

	static String _hex_pad(uint32_t num) {
		Vector<char> ret;
		ret.resize(sizeof(num) * 2);
		for (uint64_t i = 0; i < sizeof(num) * 2; ++i) {
			uint8_t four_bits = (num >> (sizeof(num) * 8 - (i + 1) * 4)) & 0xF;
			ret.write[i] = _hex_char(four_bits);
		}
		return String::utf8(ret.ptr(), ret.size());
	}

public:
	uint32_t high_bits;
	uint32_t mid_bits;
	uint32_t low_bits;

	String str() const {
		return _hex_pad(high_bits) + _hex_pad(mid_bits) + _hex_pad(low_bits);
	}

	PbxId &operator++() {
		low_bits++;
		if (!low_bits) {
			mid_bits++;
			if (!mid_bits) {
				high_bits++;
			}
		}

		return *this;
	}
};

struct ExportLibsData {
	Vector<String> lib_paths;
	String dest_dir;
};

// TODO: Find a way to minimize remove the body of this function
void EditorExportPlatformIOS::_add_assets_to_project(const Ref<EditorExportPreset> &p_preset, Vector<uint8_t> &p_project_data, const Vector<IOSExportAsset> &p_additional_assets) {
	Vector<Ref<EditorExportPlugin> > export_plugins = EditorExport::get_singleton()->get_export_plugins();
	Vector<String> frameworks;
	for (int i = 0; i < export_plugins.size(); ++i) {
		Vector<String> plugin_frameworks = export_plugins[i]->get_ios_frameworks();
		for (int j = 0; j < plugin_frameworks.size(); ++j) {
			frameworks.push_back(plugin_frameworks[j]);
		}
	}

	// that is just a random number, we just need Godot IDs not to clash with
	// existing IDs in the project.
	PbxId current_id = { 0x58938401, 0, 0 };
	String pbx_files;
	String pbx_frameworks_build;
	String pbx_frameworks_refs;
	String pbx_resources_build;
	String pbx_resources_refs;

	const String file_info_format = String("$build_id = {isa = PBXBuildFile; fileRef = $ref_id; };\n") +
									"$ref_id = {isa = PBXFileReference; lastKnownFileType = $file_type; name = $name; path = \"$file_path\"; sourceTree = \"<group>\"; };\n";
	for (int i = 0; i < p_additional_assets.size(); ++i) {
		String build_id = (++current_id).str();
		String ref_id = (++current_id).str();
		const IOSExportAsset &asset = p_additional_assets[i];

		String type;
		if (asset.exported_path.ends_with(".framework")) {
			type = "wrapper.framework";
		} else if (asset.exported_path.ends_with(".dylib")) {
			type = "compiled.mach-o.dylib";
		} else if (asset.exported_path.ends_with(".a")) {
			type = "archive.ar";
		} else {
			type = "file";
		}

		String &pbx_build = asset.is_framework ? pbx_frameworks_build : pbx_resources_build;
		String &pbx_refs = asset.is_framework ? pbx_frameworks_refs : pbx_resources_refs;

		if (pbx_build.length() > 0) {
			pbx_build += ",\n";
			pbx_refs += ",\n";
		}
		pbx_build += build_id;
		pbx_refs += ref_id;

		Dictionary format_dict;
		format_dict["build_id"] = build_id;
		format_dict["ref_id"] = ref_id;
		format_dict["name"] = asset.exported_path.get_file();
		format_dict["file_path"] = asset.exported_path;
		format_dict["file_type"] = type;
		pbx_files += file_info_format.format(format_dict, "$_");
	}

	// We do need our ARKit framework
	if ((bool)p_preset->get("capabilities/arkit")) {

	}

	String str = String::utf8((const char *)p_project_data.ptr(), p_project_data.size());
	str = str.replace("$additional_pbx_files", pbx_files);
	str = str.replace("$additional_pbx_frameworks_build", pbx_frameworks_build);
	str = str.replace("$additional_pbx_frameworks_refs", pbx_frameworks_refs);
	str = str.replace("$additional_pbx_resources_build", pbx_resources_build);
	str = str.replace("$additional_pbx_resources_refs", pbx_resources_refs);

	CharString cs = str.utf8();
	p_project_data.resize(cs.size() - 1);
	for (int i = 0; i < cs.size() - 1; i++) {
		p_project_data.write[i] = cs[i];
	}
}

Error EditorExportPlatformIOS::_export_additional_assets(const String &p_out_dir, const Vector<String> &p_assets, bool p_is_framework, Vector<IOSExportAsset> &r_exported_assets) {
	DirAccess *filesystem_da = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);
	ERR_FAIL_COND_V_MSG(!filesystem_da, ERR_CANT_CREATE, "Cannot create DirAccess for path '" + p_out_dir + "'.");
	for (int f_idx = 0; f_idx < p_assets.size(); ++f_idx) {
		String asset = p_assets[f_idx];
		if (!asset.begins_with("res://")) {
			// either SDK-builtin or already a part of the export template
			IOSExportAsset exported_asset = { asset, p_is_framework };
			r_exported_assets.push_back(exported_asset);
		} else {
			DirAccess *da = DirAccess::create_for_path(asset);
			if (!da) {
				memdelete(filesystem_da);
				ERR_FAIL_V_MSG(ERR_CANT_CREATE, "Can't create directory: " + asset + ".");
			}
			bool file_exists = da->file_exists(asset);
			bool dir_exists = da->dir_exists(asset);
			if (!file_exists && !dir_exists) {
				memdelete(da);
				memdelete(filesystem_da);
				return ERR_FILE_NOT_FOUND;
			}
			String additional_dir = p_is_framework && asset.ends_with(".dylib") ? "/dylibs/" : "/";
			String destination_dir = p_out_dir + additional_dir + asset.get_base_dir().replace("res://", "");
			if (!filesystem_da->dir_exists(destination_dir)) {
				Error make_dir_err = filesystem_da->make_dir_recursive(destination_dir);
				if (make_dir_err) {
					memdelete(da);
					memdelete(filesystem_da);
					return make_dir_err;
				}
			}

			String destination = destination_dir.plus_file(asset.get_file());
			Error err = dir_exists ? da->copy_dir(asset, destination) : da->copy(asset, destination);
			memdelete(da);
			if (err) {
				memdelete(filesystem_da);
				return err;
			}
			IOSExportAsset exported_asset = { destination, p_is_framework };
			r_exported_assets.push_back(exported_asset);
		}
	}
	memdelete(filesystem_da);

	return OK;
}

Error EditorExportPlatformIOS::_export_additional_assets(const String &p_out_dir, const Vector<SharedObject> &p_libraries, Vector<IOSExportAsset> &r_exported_assets) {
	Vector<Ref<EditorExportPlugin> > export_plugins = EditorExport::get_singleton()->get_export_plugins();
	for (int i = 0; i < export_plugins.size(); i++) {
		Vector<String> frameworks = export_plugins[i]->get_ios_frameworks();
		Error err = _export_additional_assets(p_out_dir, frameworks, true, r_exported_assets);
		ERR_FAIL_COND_V(err, err);
		Vector<String> ios_bundle_files = export_plugins[i]->get_ios_bundle_files();
		err = _export_additional_assets(p_out_dir, ios_bundle_files, false, r_exported_assets);
		ERR_FAIL_COND_V(err, err);
	}

	Vector<String> library_paths;
	for (int i = 0; i < p_libraries.size(); ++i) {
		library_paths.push_back(p_libraries[i].path);
	}
	Error err = _export_additional_assets(p_out_dir, library_paths, true, r_exported_assets);
	ERR_FAIL_COND_V(err, err);

	return OK;
}

Vector<String> EditorExportPlatformIOS::_get_preset_architectures(const Ref<EditorExportPreset> &p_preset) {
	Vector<String> enabled_archs;

	Vector<ExportArchitecture> all_archs = _get_supported_architectures();
	for (int i = 0; i < all_archs.size(); ++i) {
		// Is this specific architecture enabled in our export settings?
		if (p_preset->get("architectures/" + all_archs[i].name)) {
			enabled_archs.push_back(all_archs[i].name);
		}
	}

	return enabled_archs;
}

// Modifies xcodeproj file to add modules based on capabilities
void EditorExportPlatformIOS::add_module_code(const Ref<EditorExportPreset> &p_preset, EditorExportPlatformIOS::IOSConfigData &p_config_data, const String &p_name, const String &p_fid, const String &p_gid) {
	if ((bool)p_preset->get("capabilities/" + p_name)) {
		//add module static library
		print_line("ADDING MODULE: " + p_name);

		p_config_data.modules_buildfile += p_gid + " /* libgodot_" + p_name + "_module.a in Frameworks */ = {isa = PBXBuildFile; fileRef = " + p_fid + " /* libgodot_" + p_name + "_module.a */; };\n\t\t";
		p_config_data.modules_fileref += p_fid + " /* libgodot_" + p_name + "_module.a */ = {isa = PBXFileReference; lastKnownFileType = archive.ar; name = godot_" + p_name + "_module ; path = \"libgodot_" + p_name + "_module.a\"; sourceTree = \"<group>\"; };\n\t\t";
		p_config_data.modules_buildphase += p_gid + " /* libgodot_" + p_name + "_module.a */,\n\t\t\t\t";
		p_config_data.modules_buildgrp += p_fid + " /* libgodot_" + p_name + "_module.a */,\n\t\t\t\t";
	} else {
		//add stub function for disabled module
		p_config_data.cpp_code += "void register_" + p_name + "_types() { /*stub*/ };\n";
		p_config_data.cpp_code += "void unregister_" + p_name + "_types() { /*stub*/ };\n";
	}
}

String get_core_path(const String &p_path) {
	return p_path.get_base_dir() + "/" + p_path.get_file().get_basename();
}

String get_xcodeproj_path(const String &p_path) {
	return get_core_path(p_path) + ".xcodeproj";
}

// Error write_file_one_shot

Error EditorExportPlatformIOS::export_project(const Ref<EditorExportPreset> &p_preset, bool p_debug, const String &p_path, int p_flags) {
	ExportNotifier notifier(*this, p_preset, p_debug, p_path, p_flags);

	String src_pkg_name;
	String dest_dir = p_path.get_base_dir() + "/";
	String binary_name = p_path.get_file().get_basename();

	EditorProgress ep("export", "Exporting for iOS", 5, true);

	String team_id = p_preset->get("application/app_store_team_id");
	ERR_FAIL_COND_V_MSG(team_id.length() == 0, ERR_CANT_OPEN, "App Store Team ID not specified! Cannot configure code signing for the project.");

	if (p_debug)
		src_pkg_name = p_preset->get("custom_package/debug");
	else
		src_pkg_name = p_preset->get("custom_package/release");

	if (src_pkg_name == "") {
		String err;
		src_pkg_name = find_export_template("iphone.zip", &err);
		if (src_pkg_name == "") {
			EditorNode::add_io_error(err);
			return ERR_FILE_NOT_FOUND;
		}
	}

	if (!DirAccess::exists(dest_dir)) {
		return ERR_FILE_BAD_PATH;
	}

	DirAccess *da = DirAccess::create(DirAccess::ACCESS_FILESYSTEM);
	if (da) {
		// Save starting directory
		String current_dir = da->get_current_dir();

		// TODO: Find a less destructive way to handle this path
		// remove leftovers from last export so they don't interfere
		// in case some files are no longer needed
		
		// Wipe Xcode project
		if (da->change_dir(get_xcodeproj_path(p_path)) == OK) {
			da->erase_contents_recursive();
		}

		// Wipe Source
		if (da->change_dir(get_core_path(p_path)) == OK) {
			da->erase_contents_recursive();
		}

		// Return to starting directory
		da->change_dir(current_dir);

		// Recreate the source folder if missing
		if (!da->dir_exists(get_core_path(p_path))) {
			Error err = da->make_dir(get_core_path(p_path));
			if (err) {
				memdelete(da);
				return err;
			}
		}
		memdelete(da);
	}

	if (ep.step("Making .pck", 0)) {
		return ERR_SKIP;
	}
	String pack_path = get_core_path(p_path) + ".pck";
	Vector<SharedObject> libraries;
	Error err = save_pack(p_preset, pack_path, &libraries);
	if (err)
		return err;

	if (ep.step("Extracting and configuring Xcode project", 1)) {
		return ERR_SKIP;
	}

	String library_to_use = "libgodot.iphone." + String(p_debug ? "debug" : "release") + ".fat.a";
	print_line("Static library to link: " + library_to_use);
	String pkg_name = p_preset->get("application/name");
	if (pkg_name == "") {
		pkg_name = String(ProjectSettings::get_singleton()->get("application/config/name"));
		if (pkg_name == "") {
			pkg_name = "Unnamed";
		}
	}

	const String project_file = "godot_ios.xcodeproj/project.pbxproj";
	Set<String> files_to_parse;
	files_to_parse.insert("godot_ios/Info.plist");
	files_to_parse.insert(project_file);
	files_to_parse.insert("godot_ios/dummy.cpp");
	files_to_parse.insert("godot_ios.xcodeproj/project.xcworkspace/contents.xcworkspacedata");
	files_to_parse.insert("godot_ios.xcodeproj/xcshareddata/xcschemes/godot_ios.xcscheme");

	Set<String> files_to_append;
	files_to_append.insert("godot_ios/godot.xcconfig");

	IOSConfigData config_data = {
		pkg_name,
		binary_name,
		_get_additional_plist_content(),
		String(" ").join(_get_preset_architectures(p_preset)),
		_get_linker_flags(),
		_get_cpp_code(),
		"",
		"",
		"",
		""
	};

	DirAccess *tmp_app_path = DirAccess::create_for_path(dest_dir);
	ERR_FAIL_COND_V(!tmp_app_path, ERR_CANT_CREATE);

	print_line("Unzipping...");
	FileAccess *src_f = NULL;
	zlib_filefunc_def io = zipio_create_io_from_file(&src_f);
	unzFile src_pkg_zip = unzOpen2(src_pkg_name.utf8().get_data(), &io);
	if (!src_pkg_zip) {
		EditorNode::add_io_error("Could not open export template (not a zip file?):\n" + src_pkg_name);
		return ERR_CANT_OPEN;
	}

	add_module_code(p_preset, config_data, "arkit", "F9B95E6E2391205500AF0000", "F9C95E812391205C00BF0000");
	add_module_code(p_preset, config_data, "camera", "F9B95E6E2391205500AF0001", "F9C95E812391205C00BF0001");

	//export rest of the files
	bool found_library = false;
	int total_size = 0;
	int ret = unzGoToFirstFile(src_pkg_zip);
	Vector<uint8_t> project_file_data;
	while (ret == UNZ_OK) {
#if defined(OSX_ENABLED) || defined(X11_ENABLED)
		bool is_execute = false;
#endif

		//get filename
		unz_file_info info;
		char fname[16384];
		ret = unzGetCurrentFileInfo(src_pkg_zip, &info, fname, 16384, NULL, 0, NULL, 0);

		String file = fname;

		print_line("READ: " + file);
		Vector<uint8_t> data;
		data.resize(info.uncompressed_size);

		//read
		unzOpenCurrentFile(src_pkg_zip);
		unzReadCurrentFile(src_pkg_zip, data.ptrw(), data.size());
		unzCloseCurrentFile(src_pkg_zip);

		//write

		file = file.replace_first("iphone/", "");

		if (files_to_parse.has(file)) {
			_fix_config_file(p_preset, data, config_data, p_debug);
		} else if (files_to_append.has(file)) {
			_append_to_file(p_preset, data, config_data, p_debug);
		} else if (file.begins_with("libgodot.iphone")) {
			if (file != library_to_use) {
				ret = unzGoToNextFile(src_pkg_zip);
				continue; //ignore!
			}
			found_library = true;
#if defined(OSX_ENABLED) || defined(X11_ENABLED)
			is_execute = true;
#endif
			file = "godot_ios.a";
		} else if (file.begins_with("libgodot_arkit")) {
			if ((bool)p_preset->get("capabilities/arkit") && file.ends_with(String(p_debug ? "debug" : "release") + ".fat.a")) {
				file = "libgodot_arkit_module.a";
			} else {
				ret = unzGoToNextFile(src_pkg_zip);
				continue; //ignore!
			}
		} else if (file.begins_with("libgodot_camera")) {
			if ((bool)p_preset->get("capabilities/camera") && file.ends_with(String(p_debug ? "debug" : "release") + ".fat.a")) {
				file = "libgodot_camera_module.a";
			} else {
				ret = unzGoToNextFile(src_pkg_zip);
				continue; //ignore!
			}
		}
		if (file == project_file) {
			project_file_data = data;
		}

		///@TODO need to parse logo files

		if (data.size() > 0) {
			file = file.replace("godot_ios", binary_name);
			print_line("ADDING: " + file + " size: " + itos(data.size()));
			total_size += data.size();

			/* write it into our folder structure */
			file = dest_dir + file;

			/* make sure this folder exists */
			String dir_name = file.get_base_dir();
			if (!tmp_app_path->dir_exists(dir_name)) {
				print_line("Creating directory: " + dir_name);
				Error dir_err = tmp_app_path->make_dir_recursive(dir_name);
				if (dir_err) {
					ERR_PRINTS("Can't create '" + dir_name + "'.");
					unzClose(src_pkg_zip);
					memdelete(tmp_app_path);
					return ERR_CANT_CREATE;
				}
			}

			/* write the file */
			FileAccess *f = FileAccess::open(file, FileAccess::WRITE);
			if (!f) {
				ERR_PRINTS("Can't write '" + file + "'.");
				unzClose(src_pkg_zip);
				memdelete(tmp_app_path);
				return ERR_CANT_CREATE;
			}
			f->store_buffer(data.ptr(), data.size());
			f->close();
			memdelete(f);

#if defined(OSX_ENABLED) || defined(X11_ENABLED)
			if (is_execute) {
				// we need execute rights on this file
				chmod(file.utf8().get_data(), 0755);
			}
#endif
		}

		ret = unzGoToNextFile(src_pkg_zip);
	}

	/* we're done with our source zip */
	unzClose(src_pkg_zip);

	if (!found_library) {
		ERR_PRINTS("Requested template library '" + library_to_use + "' not found. It might be missing from your template .ZIP archive.");
		memdelete(tmp_app_path);
		return ERR_FILE_NOT_FOUND;
	}

	String iconset_dir = get_core_path(p_path) + "/Images.xcassets/AppIcon.appiconset/";
	print_line("Writing to iconset_dir: " + iconset_dir);
	err = OK;
	if (!tmp_app_path->dir_exists(iconset_dir)) {
		err = tmp_app_path->make_dir_recursive(iconset_dir);
	}
	memdelete(tmp_app_path);
	if (err)
		return err;

	err = _export_icons(p_preset, iconset_dir);
	if (err)
		return err;

	print_line("Exporting additional assets to destination: " + dest_dir);
	Vector<IOSExportAsset> assets;
	_export_additional_assets(get_core_path(p_path), libraries, assets);
	_add_assets_to_project(p_preset, project_file_data, assets);
	String project_file_name = get_xcodeproj_path(p_path) + "/project.pbxproj";
	FileAccess *f = FileAccess::open(project_file_name, FileAccess::WRITE);
	if (!f) {
		ERR_PRINTS("Can't write '" + project_file_name + "'.");
		return ERR_CANT_CREATE;
	}
	f->store_buffer(project_file_data.ptr(), project_file_data.size());
	f->close();
	memdelete(f);

#ifdef OSX_ENABLED
	if (ep.step("Code-signing dylibs", 2)) {
		return ERR_SKIP;
	}
	DirAccess *dylibs_dir = DirAccess::open(dest_dir + binary_name + "/dylibs");
	ERR_FAIL_COND_V(!dylibs_dir, ERR_CANT_OPEN);
	CodesignData codesign_data(p_preset, p_debug);
	err = _walk_dir_recursive(dylibs_dir, _codesign, &codesign_data);
	memdelete(dylibs_dir);
	ERR_FAIL_COND_V(err, err);

	if (ep.step("Making .xcarchive", 3)) {
		return ERR_SKIP;
	}
	String archive_path = p_path.get_basename() + ".xcarchive";
	List<String> archive_args;
	archive_args.push_back("-project");
	archive_args.push_back(get_xcodeproj_path(p_path));
	archive_args.push_back("-scheme");
	archive_args.push_back(binary_name);
	archive_args.push_back("-sdk");
	archive_args.push_back("iphoneos");
	archive_args.push_back("-configuration");
	archive_args.push_back(p_debug ? "Debug" : "Release");
	archive_args.push_back("-destination");
	archive_args.push_back("generic/platform=iOS");
	archive_args.push_back("archive");
	archive_args.push_back("-archivePath");
	archive_args.push_back(archive_path);
	archive_args.push_back("-allowProvisioningUpdates");
	err = OS::get_singleton()->execute("xcodebuild", archive_args, true);
	ERR_FAIL_COND_V(err, err);

	if (ep.step("Making .ipa", 4)) {
		return ERR_SKIP;
	}
	List<String> export_args;
	export_args.push_back("-exportArchive");
	export_args.push_back("-archivePath");
	export_args.push_back(archive_path);
	export_args.push_back("-exportOptionsPlist");
	export_args.push_back(get_core_path(p_path) + "/export_options_" + String(p_debug ? "ad_hoc" : "app_store") + ".plist");
	export_args.push_back("-allowProvisioningUpdates");
	export_args.push_back("-exportPath");
	export_args.push_back(dest_dir);
	err = OS::get_singleton()->execute("xcodebuild", export_args, true);
	ERR_FAIL_COND_V(err, err);
#else
	print_line(".ipa can only be built on macOS. Leaving Xcode project without building the package.");
#endif

	return OK;
}

bool EditorExportPlatformIOS::can_export(const Ref<EditorExportPreset> &p_preset, String &r_error, bool &r_missing_templates) const {

	r_missing_templates = !exists_export_template("iphone.zip", NULL);
	if (p_preset->get("custom_package/debug") != "") {
		if (FileAccess::exists(p_preset->get("custom_package/debug"))) {
			r_missing_templates = false;
		}
	}
	if (p_preset->get("custom_package/release") != "") {
		if (FileAccess::exists(p_preset->get("custom_package/release"))) {
			r_missing_templates = false;
		}
	}

	String err;
	if (r_missing_templates) {
		err += TTR("Missing release template. Either download the official templates or specify a debug or release template path.") + "\n";
	}

	if (p_preset->get("application/app_store_team_id") == "") {
		err += TTR("App Store Team ID not specified - cannot configure the project.") + "\n";
	}

	String name_err;
	if (!is_package_name_valid(p_preset->get("application/identifier"), &name_err)) {
		err += TTR("Invalid Identifier: ") + name_err + "\n";
	}

	String etc_error = test_etc2();
	if (etc_error != "") {
		err += etc_error;
	}

	if (!err.empty()) {
		r_error = err;
		return false;
	}
	return true;
}

EditorExportPlatformIOS::EditorExportPlatformIOS() {

	Ref<Image> img = memnew(Image(_iphone_logo));
	logo.instance();
	logo->create_from_image(img);
}

EditorExportPlatformIOS::~EditorExportPlatformIOS() {
}

void register_iphone_exporter() {

	Ref<EditorExportPlatformIOS> platform;
	platform.instance();

	EditorExport::get_singleton()->add_export_platform(platform);
}
