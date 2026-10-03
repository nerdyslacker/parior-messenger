package parior_messenger

import "core:fmt"
import "core:strings"

import "gui:skald"

endpoint_changed :: proc(value: string) -> Msg {
	clean, _ := strings.replace_all(value, "\n", "", context.temp_allocator)
	return Endpoint_Changed(clean)
}

cancel_add_peer :: proc() -> Msg {
	return Cancel_Add_Peer{}
}

cancel_remove_peer :: proc() -> Msg {
	return Cancel_Remove_Peer{}
}

peer_menu_action :: proc(index: int) -> Msg {
	return Peer_Menu_Action(index)
}

peer_sidebar :: proc(state: State, ctx: ^skald.Ctx(Msg), size: [2]f32) -> skald.View {
	theme := ctx.theme
	content_width := max(f32(0), size.x - 2 * theme.spacing.lg)
	card_width := max(f32(0), content_width)
	text_width := max(f32(0), content_width - 2 * theme.spacing.sm)
	peer_avatar_size: f32 = 36
	details_width := max(f32(0), text_width - peer_avatar_size - theme.spacing.sm)
	rows := make([dynamic]skald.View, 0, max(1, len(state.peers)), context.temp_allocator)
	peer_order := make([dynamic]int, 0, len(state.peers), context.temp_allocator)
	for peer, index in state.peers {
		if peer.pinned {
			append(&peer_order, index)
		}
	}
	for peer, index in state.peers {
		if !peer.pinned {
			append(&peer_order, index)
		}
	}
	for index in peer_order {
		peer := state.peers[index]
		selected := peer.id == state.selected_peer_id
		row_id := skald.hash_id(fmt.tprintf("peer-%d-row", peer.id))
		connection := fmt.tprintf("%v · %v", peer.connection, peer.presence)
		children := make([dynamic]skald.View, 0, 4, context.temp_allocator)
		foreground := theme.color.fg
		muted := theme.color.fg_muted
		background := theme.color.surface
		if selected {
			foreground = theme.color.on_primary
			muted = theme.color.on_primary
			background = theme.color.primary
		} else if skald.widget_hovered(ctx, row_id) {
			background = theme.color.elevated
		}
		peer_label := peer.endpoint
		if peer.pinned {
			peer_label = fmt.tprintf("📌 %s", peer.endpoint)
		}
		label_width := details_width
		if peer.unread > 0 {
			label_width = max(f32(0), details_width - 40 - theme.spacing.xs)
		}
		title_children := make([dynamic]skald.View, 0, 3, context.temp_allocator)
		append(&title_children, skald.text(peer_label, foreground, theme.font.size_md,
			max_width = label_width, overflow = .Ellipsis))
		append(&title_children, skald.flex(1, skald.spacer(0)))
		if peer.unread > 0 {
			append(&title_children, skald.badge(ctx, fmt.tprintf("%d", peer.unread), tone = .Danger))
		}
		append(&children, skald.row(..title_children[:],
			width = details_width, spacing = theme.spacing.xs, cross_align = .Center))
		append(&children, skald.text(connection, muted, theme.font.size_sm,
			max_width = details_width, overflow = .Ellipsis))
		if peer.typing {
			append(&children, skald.text("typing…", selected ? theme.color.on_primary : theme.color.primary, theme.font.size_sm))
		}
		if len(peer.status) > 0 {
			append(&children, skald.text(peer.status, muted, theme.font.size_sm,
				max_width = details_width, overflow = .Ellipsis))
		}
		details := skald.col(..children[:],
			spacing = theme.spacing.xs, width = details_width, cross_align = .Stretch)
		body := skald.row(
			peer_avatar_view(peer, ctx, peer_avatar_size),
			details,
			spacing = theme.spacing.sm, padding = theme.spacing.sm, width = card_width,
			bg = background, radius = theme.radius.sm, cross_align = .Center)
		row := skald.col(body, skald.spacer(theme.spacing.sm), width = card_width, cross_align = .Stretch)
		append(&rows, skald.clickable(ctx, row, Select_Peer(peer.id), Peer_Context(peer.id), id = row_id))
	}
	if len(rows) == 0 {
		append(&rows, skald.text("No peers yet", theme.color.fg_muted, theme.font.size_md))
	}

	dialog_width := min(f32(420), max(f32(240), size.x - 2 * theme.spacing.xl))
	dialog_content_width := max(f32(0), dialog_width - 2 * theme.spacing.lg)
	add_dialog := skald.dialog(ctx,
		open = state.add_peer_open,
		on_dismiss = cancel_add_peer,
		content = skald.col(
			skald.text("Add peer", theme.color.fg, theme.font.size_lg),
			skald.text("Use the peer's configured IPv6 address and listening port. Both users must add each other.",
				theme.color.fg_muted, theme.font.size_sm, max_width = dialog_content_width),
			skald.text_input(ctx, state.endpoint_draft, endpoint_changed,
				id = skald.hash_id("peer-endpoint"), placeholder = "name@[address]:port",
				width = dialog_content_width, height = 64, multiline = true, wrap = true),
			skald.row(
				skald.flex(1, skald.spacer(0)),
				skald.button(ctx, "Cancel", Msg(Cancel_Add_Peer{}),
					id = skald.hash_id("cancel-add-peer"), bg = theme.color.surface, fg = theme.color.fg),
				skald.button(ctx, "Add", Msg(Add_Peer{}), id = skald.hash_id("add-peer")),
				spacing = theme.spacing.sm, cross_align = .Center),
			width = dialog_width, spacing = theme.spacing.sm, padding = theme.spacing.lg,
			cross_align = .Stretch))
	remove_endpoint := "this peer"
	if index, found := peer_index(state, state.remove_peer_id); found {
		remove_endpoint = state.peers[index].endpoint
	}
	remove_dialog := skald.dialog(ctx,
		open = state.remove_peer_open,
		on_dismiss = cancel_remove_peer,
		content = skald.col(
			skald.text("Remove peer?", theme.color.fg, theme.font.size_lg),
			skald.text(remove_endpoint, theme.color.fg_muted, theme.font.size_md, max_width = dialog_content_width),
			skald.text("The contact will be removed from this device.", theme.color.fg_muted, theme.font.size_sm, max_width = dialog_content_width),
			skald.row(
				skald.flex(1, skald.spacer(0)),
				skald.button(ctx, "Cancel", Msg(Cancel_Remove_Peer{}),
					id = skald.hash_id("cancel-remove-peer"), bg = theme.color.surface, fg = theme.color.fg),
				skald.button(ctx, "Remove", Msg(Confirm_Remove_Peer{}),
					id = skald.hash_id("confirm-remove-peer")),
				spacing = theme.spacing.sm, cross_align = .Center),
			width = dialog_width, spacing = theme.spacing.sm, padding = theme.spacing.lg,
			cross_align = .Stretch))

	peer_list := skald.col(..rows[:], cross_align = .Stretch)
	if len(state.peers) > 0 {
		menu_items := [2]string{"Pin", "Remove"}
		if index, found := peer_index(state, state.context_peer_id); found && state.peers[index].pinned {
			menu_items[0] = "Unpin"
		}
		peer_list = skald.context_menu(ctx, peer_list, menu_items[:], peer_menu_action,
			id = skald.hash_id("peer-context-menu"), width = 160)
	}

	return skald.col(
		skald.row(
			skald.text("Peers", theme.color.fg, theme.font.size_xl),
			skald.button(ctx, "Add", Msg(Open_Add_Peer{}),
				id = skald.hash_id("open-add-peer")),
			skald.flex(1, skald.spacer(0)),
			settings_view(state, ctx),
			width = content_width, spacing = theme.spacing.sm, cross_align = .Center),
		skald.divider(ctx),
		skald.flex(1, skald.scroll(ctx, {content_width, 0}, peer_list,
			id = skald.hash_id("peer-list"))),
		self_profile_view(state, ctx, content_width),
		add_dialog,
		remove_dialog,
		width = size.x, height = size.y, spacing = theme.spacing.sm, padding = theme.spacing.lg,
		bg = theme.color.bg, cross_align = .Stretch)
}
