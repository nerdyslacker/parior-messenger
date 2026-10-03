package parior_messenger

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

import "barev:barev"
import "gui:skald"

active_client: ^barev.Client
active_config_path: string
active_contacts_path: string
active_pins_path: string
startup_config: App_Config
startup_needs_onboarding: bool
active_client_initialized: bool
active_client_started: bool
startup_avatar_loaded: bool
active_window_title: string
startup_error: string

print_usage :: proc() {
	fmt.println("usage: parior [--profile NAME] [nickname [bind-ipv6 [port]]]")
}

start_active_client :: proc(config: App_Config) -> barev.Error {
	options := barev.default_options(config.nickname, config.bind_address)
	options.port = config.port
	if result := barev.client_init(active_client, options); result != .None {
		return result
	}
	active_client_initialized = true
	if result := barev.client_start(active_client); result != .None {
		barev.client_destroy(active_client)
		active_client_initialized = false
		return result
	}
	active_client_started = true
	if result := barev.client_set_presence(active_client, .Available); result != .None {
		barev.client_stop(active_client)
		barev.client_destroy(active_client)
		active_client_initialized = false
		active_client_started = false
		return result
	}
	startup_avatar_loaded = false
	if len(config.avatar_path) > 0 {
		mime := avatar_mime_for_path(config.avatar_path)
		if len(mime) > 0 {
			if data, read_err := os.read_entire_file(config.avatar_path, context.allocator); read_err == nil {
				if avatar_data_valid(data) && barev.client_set_avatar(active_client, data, mime) == .None {
					startup_avatar_loaded = true
				}
				delete(data)
			}
		}
	}
	if os.exists(active_contacts_path) {
		_ = barev.client_load_contacts(active_client, active_contacts_path)
	}
	return .None
}

main :: proc() {
	args := os.args
	argument := 1
	profile := ""
	if argument < len(args) && args[argument] == "--help" {
		print_usage()
		return
	}
	if argument < len(args) && args[argument] == "--profile" {
		if argument + 1 >= len(args) || !valid_profile_name(args[argument + 1]) {
			fmt.eprintln("Profile names may contain only letters, numbers, '-' and '_'")
			print_usage()
			return
		}
		profile = args[argument + 1]
		argument += 2
	} else if argument < len(args) && strings.has_prefix(args[argument], "--profile=") {
		profile = args[argument][len("--profile="):]
		if !valid_profile_name(profile) {
			fmt.eprintln("Profile names may contain only letters, numbers, '-' and '_'")
			print_usage()
			return
		}
		argument += 1
	}
	if len(args) - argument > 3 {
		print_usage()
		return
	}

	config_path, contacts_path, pins_path, paths_ok := prepare_app_paths(profile)
	if !paths_ok {
		fmt.eprintln("Could not prepare the application configuration directory")
		return
	}
	active_config_path = config_path
	active_contacts_path = contacts_path
	active_pins_path = pins_path
	defer delete(active_config_path)
	defer delete(active_contacts_path)
	defer delete(active_pins_path)

	config, configured := load_config(active_config_path)
	startup_config = config
	defer destroy_config(&startup_config)

	if argument < len(args) {
		replace_string(&startup_config.nickname, args[argument])
		configured = true
		argument += 1
	}
	if argument < len(args) {
		replace_string(&startup_config.bind_address, args[argument])
		configured = true
		argument += 1
	}
	if argument < len(args) {
		parsed_port, ok := strconv.parse_u64(args[argument])
		if !ok || parsed_port == 0 || parsed_port > u64(max(u16)) {
			fmt.eprintf("Invalid port %q\n", args[argument])
			return
		}
		startup_config.port = u16(parsed_port)
		configured = true
	}
	startup_needs_onboarding = !configured
	startup_error = strings.clone("")
	defer delete(startup_error)
	active_window_title = strings.clone("Parior Messenger")
	if len(profile) > 0 {
		delete(active_window_title)
		active_window_title = fmt.aprintf("Parior Messenger — %s", profile)
	}
	defer delete(active_window_title)

	client := new(barev.Client)
	if client == nil {
		fmt.eprintln("Could not allocate Barev client")
		return
	}
	defer free(client)

	active_client = client
	if configured {
		if result := start_active_client(startup_config); result != .None {
			startup_needs_onboarding = true
			delete(startup_error)
			startup_error = fmt.aprintf(
				"Could not start Barev on port %d: %v. The address or port may already be in use.",
				startup_config.port, result)
			fmt.eprintln(startup_error)
		}
	}
	skald.run(make_app())
	if active_client_started {
		barev.client_stop(client)
	}
	if active_client_initialized {
		barev.client_destroy(client)
	}
	active_client = nil
}
