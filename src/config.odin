package parior_messenger

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

App_Config :: struct {
	nickname:     string,
	bind_address: string,
	avatar_path:  string,
	port:         u16,
	dark_theme:   bool,
}

default_config :: proc() -> App_Config {
	return {
		nickname = strings.clone("parior"),
		bind_address = strings.clone("::1"),
		avatar_path = strings.clone(""),
		port = 5299,
		dark_theme = true,
	}
}

destroy_config :: proc(config: ^App_Config) {
	delete(config.nickname)
	delete(config.bind_address)
	delete(config.avatar_path)
	config^ = {}
}

load_config :: proc(path: string) -> (config: App_Config, loaded: bool) {
	config = default_config()
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return config, false
	}
	defer delete(data)

	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		trimmed := strings.trim_space(line)
		separator := strings.index_byte(trimmed, '=')
		if separator <= 0 {
			continue
		}
		key := trimmed[:separator]
		value := strings.trim_space(trimmed[separator + 1:])
		switch key {
		case "nickname":
			if len(value) > 0 {
				replace_string(&config.nickname, value)
			}
		case "bind_ipv6":
			if len(value) > 0 {
				replace_string(&config.bind_address, value)
			}
		case "port":
			if parsed, ok := strconv.parse_u64(value); ok && parsed > 0 && parsed <= u64(max(u16)) {
				config.port = u16(parsed)
			}
		case "theme":
			config.dark_theme = value != "light"
		case "avatar_path":
			replace_string(&config.avatar_path, value)
		}
	}
	return config, true
}

format_config :: proc(config: App_Config, allocator := context.allocator) -> string {
	return fmt.aprintf(
		"nickname=%s\nbind_ipv6=%s\nport=%d\ntheme=%s\navatar_path=%s\n",
		config.nickname,
		config.bind_address,
		config.port,
		config.dark_theme ? "dark" : "light",
		config.avatar_path,
		allocator = allocator,
	)
}

valid_profile_name :: proc(value: string) -> bool {
	if len(value) == 0 || len(value) > 64 {
		return false
	}
	for byte in transmute([]u8)value {
		if !(byte >= 'a' && byte <= 'z' || byte >= 'A' && byte <= 'Z' ||
		     byte >= '0' && byte <= '9' || byte == '-' || byte == '_') {
			return false
		}
	}
	return true
}

prepare_app_paths :: proc(profile: string = "") -> (config_path, contacts_path, pins_path: string, ok: bool) {
	root, err := os.user_config_dir(context.allocator)
	if err != nil {
		return
	}
	defer delete(root)
	directory := fmt.aprintf("%s/parior-messenger", root)
	if len(profile) > 0 {
		profile_directory := fmt.aprintf("%s/%s", directory, profile)
		delete(directory)
		directory = profile_directory
	}
	defer delete(directory)
	if mkdir_err := os.make_directory_all(directory); mkdir_err != nil && mkdir_err != .Exist {
		return
	}
	if !os.is_directory(directory) {
		return
	}
	return fmt.aprintf("%s/config", directory), fmt.aprintf("%s/contacts", directory), fmt.aprintf("%s/pins", directory), true
}
