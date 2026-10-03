package parior_messenger

import "core:fmt"
import "core:path/filepath"
import "core:strings"

import "barev:barev"
import "gui:skald"

Transfer_Row :: struct {
	id:          u64,
	peer_id:     u64,
	direction:   barev.Transfer_Direction,
	state:       barev.Transfer_State,
	filename:    string,
	path:        string,
	size:        i64,
	transferred: i64,
	error:       barev.Error,
	dialog_pending: bool,
	dialog_dismissed: bool,
}

transfer_index :: proc(state: State, id: u64) -> (int, bool) {
	for value, index in state.transfers {
		if value.id == id {
			return index, true
		}
	}
	return 0, false
}

sync_transfer_from_client :: proc(state: ^State, id: u64, transfer_error: barev.Error = .None) -> bool {
	info, ok := barev.client_get_transfer(state.client, id)
	if !ok {
		return false
	}
	index, found := transfer_index(state^, id)
	if !found {
		append(&state.transfers, Transfer_Row {
			id = info.id,
			peer_id = info.peer_id,
			direction = info.direction,
			state = info.state,
			filename = strings.clone(info.filename),
			path = strings.clone(info.path),
			size = info.size,
			transferred = info.transferred,
			error = transfer_error,
		})
		return true
	}
	value := &state.transfers[index]
	value.peer_id = info.peer_id
	value.direction = info.direction
	value.state = info.state
	value.size = info.size
	value.transferred = info.transferred
	value.error = transfer_error
	if value.filename != info.filename {
		replace_string(&value.filename, info.filename)
	}
	if value.path != info.path {
		replace_string(&value.path, info.path)
	}
	return true
}

activate_next_transfer_offer :: proc(state: ^State) {
	if state.transfer_dialog_id != 0 {
		return
	}
	for value in state.transfers {
		if value.dialog_pending {
			state.transfer_dialog_id = value.id
			if index, found := transfer_index(state^, value.id); found {
				state.transfers[index].dialog_pending = false
			}
			return
		}
	}
}

queue_transfer_dialog :: proc(state: ^State, id: u64) {
	index, found := transfer_index(state^, id)
	if !found || state.transfer_dialog_id == id || state.transfers[index].dialog_dismissed {
		return
	}
	if state.transfer_dialog_id == 0 {
		state.transfer_dialog_id = id
		state.transfers[index].dialog_pending = false
	} else {
		state.transfers[index].dialog_pending = true
	}
}

destroy_transfers_for_peer :: proc(state: ^State, peer_id: u64) {
	index := 0
	for index < len(state.transfers) {
		if state.transfers[index].peer_id != peer_id {
			index += 1
			continue
		}
		id := state.transfers[index].id
		delete(state.transfers[index].filename)
		delete(state.transfers[index].path)
		ordered_remove(&state.transfers, index)
		if state.transfer_dialog_id == id {
			state.transfer_dialog_id = 0
		}
		if state.pending_destination_transfer_id == id {
			state.pending_destination_transfer_id = 0
		}
		clear_transfer_conflict(state, id)
	}
	activate_next_transfer_offer(state)
}

outgoing_file_chosen :: proc(result: skald.File_Dialog_Result) -> Msg {
	if result.cancelled {
		return Transfer_File_Picker_Cancelled{}
	}
	return Transfer_File_Chosen(result.path)
}

transfer_destination_chosen :: proc(result: skald.File_Dialog_Result) -> Msg {
	if result.cancelled {
		return Transfer_Destination_Cancelled{}
	}
	return Transfer_Destination_Chosen(result.path)
}

transfer_dialog_dismissed :: proc() -> Msg {
	return Dismiss_Transfer_Dialog{}
}

transfer_rename_chosen :: proc(result: skald.File_Dialog_Result) -> Msg {
	if result.cancelled {
		return Transfer_Rename_Cancelled{}
	}
	return Transfer_Rename_Chosen(result.path)
}

clear_transfer_conflict :: proc(state: ^State, id: u64) {
	if state.transfer_conflict_id != id {
		return
	}
	state.transfer_conflict_id = 0
	replace_string(&state.transfer_conflict_path, "")
}

set_transfer_conflict_path :: proc(state: ^State, id: u64, path: string) {
	state.transfer_conflict_id = id
	replace_string(&state.transfer_conflict_path, path)
	state.transfer_dialog_id = id
}

set_transfer_conflict :: proc(state: ^State, id: u64, directory: string) -> bool {
	index, found := transfer_index(state^, id)
	if !found {
		return false
	}
	path, err := filepath.join({directory, state.transfers[index].filename})
	if err != nil {
		return false
	}
	defer delete(path)
	set_transfer_conflict_path(state, id, path)
	return true
}

transfer_rename_command :: proc(state: State, id: u64) -> skald.Command(Msg) {
	directory := ""
	if state.transfer_conflict_id == id {
		directory = filepath.dir(state.transfer_conflict_path)
	}
	return skald.cmd_save_file_dialog(nil, transfer_rename_chosen, default_location = directory)
}

format_file_size :: proc(value: i64) -> string {
	if value < 1024 {
		return fmt.tprintf("%d B", value)
	}
	if value < 1024 * 1024 {
		return fmt.tprintf("%.1f KiB", f64(value) / 1024)
	}
	if value < 1024 * 1024 * 1024 {
		return fmt.tprintf("%.1f MiB", f64(value) / (1024 * 1024))
	}
	return fmt.tprintf("%.1f GiB", f64(value) / (1024 * 1024 * 1024))
}

transfer_peer_name :: proc(state: State, peer_id: u64) -> string {
	if index, found := peer_index(state, peer_id); found {
		return state.peers[index].endpoint
	}
	return "peer"
}

transfer_dialog_view :: proc(state: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	index, found := transfer_index(state, state.transfer_dialog_id)
	if !found {
		return skald.spacer(0)
	}
	value := state.transfers[index]
	theme := ctx.theme
	dialog_width: f32 = 480
	content_width := dialog_width - 2 * theme.spacing.lg
	peer_name := transfer_peer_name(state, value.peer_id)
	title := "File transfer"
	detail := fmt.tprintf("%s · %s", value.filename, format_file_size(value.size))
	status := "Waiting for the peer to accept…"
	if value.direction == .Incoming {
		status = fmt.tprintf("From %s", peer_name)
	} else {
		status = fmt.tprintf("To %s", peer_name)
	}
	progress_value: f32 = 0
	if value.size > 0 {
		progress_value = clamp(f32(value.transferred) / f32(value.size), 0, 1)
	}
	children := make([dynamic]skald.View, 0, 10, context.temp_allocator)
	append(&children, skald.text(title, theme.color.fg, theme.font.size_lg))
	append(&children, skald.text(detail, theme.color.fg, theme.font.size_md,
		max_width = content_width))
	append(&children, skald.text(status, theme.color.fg_muted, theme.font.size_sm,
		max_width = content_width))

	switch value.state {
	case .Offered:
		if value.direction == .Incoming {
			if state.transfer_conflict_id == value.id {
				append(&children, skald.text(
					"A file with this name already exists. Rename the incoming file or overwrite the existing one.",
					theme.color.warning, theme.font.size_md, max_width = content_width))
				append(&children, skald.row(
					skald.flex(1, skald.spacer(0)),
					skald.button(ctx, "Reject", Reject_Transfer(value.id),
						id = skald.hash_id(fmt.tprintf("reject-conflicting-transfer-%d", value.id)),
						bg = theme.color.surface, fg = theme.color.fg),
					skald.button(ctx, "Rename…", Rename_Transfer(value.id),
						id = skald.hash_id(fmt.tprintf("rename-transfer-%d", value.id)),
						bg = theme.color.surface, fg = theme.color.fg),
					skald.button(ctx, "Overwrite", Overwrite_Transfer(value.id),
						id = skald.hash_id(fmt.tprintf("overwrite-transfer-%d", value.id)),
						bg = theme.color.danger, fg = theme.color.on_primary),
					spacing = theme.spacing.sm, cross_align = .Center))
			} else {
				append(&children, skald.text("Choose where to save this file, or reject the offer.",
					theme.color.fg_muted, theme.font.size_md, max_width = content_width))
				append(&children, skald.row(
					skald.flex(1, skald.spacer(0)),
					skald.button(ctx, "Reject", Reject_Transfer(value.id),
						id = skald.hash_id(fmt.tprintf("reject-transfer-%d", value.id)),
						bg = theme.color.surface, fg = theme.color.fg),
					skald.button(ctx, "Choose destination", Choose_Transfer_Destination(value.id),
						id = skald.hash_id(fmt.tprintf("accept-transfer-%d", value.id))),
					spacing = theme.spacing.sm, cross_align = .Center))
			}
		} else {
			append(&children, skald.progress(ctx, 0, width = content_width, indeterminate = true))
			append(&children, skald.row(
				skald.flex(1, skald.spacer(0)),
				skald.button(ctx, "Cancel", Cancel_Transfer(value.id),
					id = skald.hash_id(fmt.tprintf("cancel-transfer-%d", value.id)),
					bg = theme.color.surface, fg = theme.color.fg),
				cross_align = .Center))
		}
	case .Accepted, .Transferring:
		progress_text := fmt.tprintf("%s of %s", format_file_size(value.transferred), format_file_size(value.size))
		append(&children, skald.progress(ctx, progress_value, width = content_width))
		append(&children, skald.text(progress_text, theme.color.fg_muted, theme.font.size_sm,
			max_width = content_width, align = .End))
		append(&children, skald.row(
			skald.flex(1, skald.spacer(0)),
			skald.button(ctx, "Cancel", Cancel_Transfer(value.id),
				id = skald.hash_id(fmt.tprintf("cancel-transfer-%d", value.id)),
				bg = theme.color.surface, fg = theme.color.fg),
			cross_align = .Center))
	case .Completed:
		append(&children, skald.progress(ctx, 1, width = content_width,
			color_fill = theme.color.success))
		append(&children, skald.text("Transfer completed successfully.",
			theme.color.success, theme.font.size_md, max_width = content_width))
		append(&children, skald.row(
			skald.flex(1, skald.spacer(0)),
			skald.button(ctx, "Close", Msg(Dismiss_Transfer_Dialog{}),
				id = skald.hash_id(fmt.tprintf("close-transfer-%d", value.id)),
				bg = theme.color.surface, fg = theme.color.fg),
			skald.button(ctx, "Open destination", Open_Transfer_Destination(value.id),
				id = skald.hash_id(fmt.tprintf("open-transfer-destination-%d", value.id)),
				bg = theme.color.surface, fg = theme.color.fg, disabled = len(value.path) == 0),
			skald.button(ctx, "Open file", Open_Transfer_File(value.id),
				id = skald.hash_id(fmt.tprintf("open-transfer-file-%d", value.id)),
				disabled = len(value.path) == 0),
			spacing = theme.spacing.sm,
			cross_align = .Center))
	case .Rejected:
		append(&children, skald.text("The file offer was rejected.",
			theme.color.fg_muted, theme.font.size_md))
		append(&children, skald.row(skald.flex(1, skald.spacer(0)),
			skald.button(ctx, "Close", Msg(Dismiss_Transfer_Dialog{}),
				id = skald.hash_id(fmt.tprintf("close-rejected-transfer-%d", value.id))), cross_align = .Center))
	case .Cancelled:
		append(&children, skald.text("The transfer was cancelled.",
			theme.color.warning, theme.font.size_md))
		append(&children, skald.row(skald.flex(1, skald.spacer(0)),
			skald.button(ctx, "Close", Msg(Dismiss_Transfer_Dialog{}),
				id = skald.hash_id(fmt.tprintf("close-cancelled-transfer-%d", value.id))), cross_align = .Center))
	case .Failed:
		title = "Transfer failed"
		children[0] = skald.text(title, theme.color.danger, theme.font.size_lg)
		append(&children, skald.text(fmt.tprintf("The transfer failed: %v", value.error),
			theme.color.danger, theme.font.size_md, max_width = content_width))
		append(&children, skald.row(skald.flex(1, skald.spacer(0)),
			skald.button(ctx, "Close", Msg(Dismiss_Transfer_Dialog{}),
				id = skald.hash_id(fmt.tprintf("close-failed-transfer-%d", value.id))), cross_align = .Center))
	}

	return skald.dialog(ctx,
		open = true,
		on_dismiss = transfer_dialog_dismissed,
		content = skald.col(..children[:],
			width = dialog_width, spacing = theme.spacing.sm, cross_align = .Stretch),
		id = skald.hash_id("transfer-dialog"), width = dialog_width)
}
