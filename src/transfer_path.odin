package parior_messenger

import "core:os"
import "core:path/filepath"
import "core:strings"

import "gui:skald"

Transfer_Path_Request :: struct {
	path:        string,
	destination: bool,
}

run_transfer_path_open :: proc(value: Transfer_Path_Request) -> Msg {
	defer delete(value.path)
	command: []string
	when ODIN_OS == .Linux {
		command = []string{"xdg-open", value.path}
	} else when ODIN_OS == .Darwin {
		command = []string{"open", value.path}
	} else when ODIN_OS == .Windows {
		command = []string{"explorer.exe", value.path}
	} else {
		return Transfer_Path_Opened{destination = value.destination, ok = false}
	}
	state, stdout, stderr, err := os.process_exec(os.Process_Desc{command = command}, context.allocator)
	defer delete(stdout)
	defer delete(stderr)
	return Transfer_Path_Opened {
		destination = value.destination,
		ok = err == nil && state.exited && state.success && state.exit_code == 0,
	}
}

transfer_path_command :: proc(value: Transfer_Row, destination: bool) -> skald.Command(Msg) {
	path := value.path
	if destination {
		path = filepath.dir(path)
	}
	request := Transfer_Path_Request {
		path = strings.clone(path),
		destination = destination,
	}
	return skald.cmd_thread(Msg, request, run_transfer_path_open)
}
