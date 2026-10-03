package parior_messenger

import "core:os"
import "core:strings"

import "gui:skald"

Desktop_Notification :: struct {
	title: string,
	body:  string,
}

desktop_notification :: proc(title, body: string) -> Desktop_Notification {
	return {
		title = strings.clone(title),
		body = strings.clone(body),
	}
}

run_desktop_notification :: proc(value: Desktop_Notification) -> Msg {
	defer delete(value.title)
	defer delete(value.body)
	ok := false
	when ODIN_OS == .Linux {
		state, stdout, stderr, err := os.process_exec(
			os.Process_Desc{
				command = []string{"notify-send", "--app-name=Parior", value.title, value.body},
			},
			context.allocator,
		)
		defer delete(stdout)
		defer delete(stderr)
		ok = err == nil && state.exited && state.success && state.exit_code == 0
	}
	return Desktop_Notification_Done(ok)
}

desktop_notification_command :: proc(value: Desktop_Notification) -> skald.Command(Msg) {
	return skald.cmd_thread(Msg, value, run_desktop_notification)
}
