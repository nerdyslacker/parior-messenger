package parior_messenger

import "core:fmt"

import "barev:barev"
import "gui:skald"

PRESENCE_OPTIONS := []string{
	"Available",
	"Away",
	"Extended Away",
	"Do not disturb",
}

AVATAR_FILTERS := []skald.File_Filter{
	{"Images", "png;jpg;jpeg;gif"},
}

avatar_dialog_result :: proc(result: skald.File_Dialog_Result) -> Msg {
	if result.cancelled {
		return Avatar_Picker_Cancelled{}
	}
	return Avatar_File_Chosen(result.path)
}

avatar_file_loaded :: proc(result: skald.File_Read_Result) -> Msg {
	return Avatar_File_Loaded {
		data = result.bytes,
		ok = result.err == .None,
	}
}

presence_label :: proc(value: barev.Presence) -> string {
	switch value {
	case .Away:          return "Away"
	case .Extended_Away: return "Extended Away"
	case .Busy:          return "Do not disturb"
	case .Offline, .Available: return "Available"
	}
	return "Available"
}

presence_changed :: proc(value: string) -> Msg {
	presence: barev.Presence = .Available
	switch value {
	case "Away":           presence = .Away
	case "Extended Away":  presence = .Extended_Away
	case "Do not disturb": presence = .Busy
	}
	return Presence_Changed(presence)
}

self_connection_action :: proc(connected: bool) -> Msg {
	return connected ? Msg(Disconnect_Self{}) : Msg(Connect_Self{})
}

self_profile_view :: proc(state: State, ctx: ^skald.Ctx(Msg), width: f32) -> skald.View {
	theme := ctx.theme
	nickname := state.nickname_draft
	initials := "?"
	if len(nickname) > 0 {
		first := nickname[0]
		if first >= 'a' && first <= 'z' {
			first -= 32
		}
		initials = fmt.tprintf("%c", first)
	}
	avatar_size: f32 = 32
	action_width: f32 = 88
	select_width := max(f32(92), width - avatar_size - action_width - 2 * theme.spacing.sm)
	action_label := state.client_connected ? "Disconnect" : "Connect"
	avatar: skald.View
	if len(state.local_avatar_path) > 0 {
		avatar = skald.image(ctx, state.local_avatar_path,
			width = avatar_size, height = avatar_size, radius = avatar_size / 2)
	} else {
		avatar = skald.avatar(ctx, initials, size = avatar_size)
	}
	avatar = skald.clickable(ctx, avatar, Msg(Open_Avatar_Picker{}),
		id = skald.hash_id("choose-local-avatar"), disabled = state.avatar_busy)
	action := skald.button(ctx, action_label, self_connection_action(state.client_connected),
		id = skald.hash_id("self-connection"), width = action_width,
		bg = theme.color.surface, fg = theme.color.fg, font_size = theme.font.size_sm)
	return skald.col(
		skald.divider(ctx),
		skald.row(
			skald.tooltip(ctx, avatar, nickname, id = skald.hash_id("local-nickname-tooltip")),
			skald.select(ctx, presence_label(state.local_presence), PRESENCE_OPTIONS[:], presence_changed,
				id = skald.hash_id("local-presence"), width = select_width, radius = theme.radius.md,
				disabled = !state.client_connected),
			action,
			width = width, spacing = theme.spacing.sm, cross_align = .Center),
		width = width, spacing = theme.spacing.sm, cross_align = .Stretch)
}
