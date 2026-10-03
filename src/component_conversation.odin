package parior_messenger

import "core:fmt"
import "core:strings"

import "gui:skald"

message_changed :: proc(value: string) -> Msg {
	return Message_Changed(value)
}

message_submitted :: proc(value: string) -> Msg {
	return Send_Message(value)
}

conversation_view :: proc(state: State, ctx: ^skald.Ctx(Msg), size: [2]f32, compact: bool) -> skald.View {
	theme := ctx.theme
	content_width := max(f32(0), size.x - 2 * theme.spacing.lg)
	message_nodes := make([dynamic]skald.View, 0, max(1, len(state.messages)), context.temp_allocator)
	visible_message_count := 0
	for entry in state.messages {
		if entry.peer_id != state.selected_peer_id {
			continue
		}
		visible_message_count += 1
		bubble_padding := theme.spacing.sm
		message_cap := max(f32(1), content_width * 0.72 - 2 * bubble_padding)
		message_max_width: f32 = 0
		message_width := f32(len(entry.text)) * theme.font.size_md * 0.55
		time_width := f32(len(entry.sent_time)) * theme.font.size_xs * 0.55
		if ctx.renderer != nil {
			message_width, _ = skald.measure_text(ctx.renderer, entry.text, theme.font.size_md)
			time_width, _ = skald.measure_text(ctx.renderer, entry.sent_time, theme.font.size_xs)
		}
		if message_width > message_cap {
			message_max_width = message_cap
		}
		bubble_inner_width := max(min(message_width, message_cap), time_width)
		bubble_width := min(content_width, bubble_inner_width + 2 * bubble_padding)
		bubble_bg := theme.color.surface
		bubble_fg := theme.color.fg
		time_fg := theme.color.fg_muted
		text_align: skald.Cross_Align = .Start
		if !entry.incoming {
			bubble_bg = skald.color_lighten(theme.color.primary, 0.12)
			bubble_fg = theme.color.on_primary
			time_fg = skald.color_mix(bubble_fg, bubble_bg, 0.38)
			text_align = .End
		}
		bubble := skald.col(
			skald.text(entry.text, bubble_fg, theme.font.size_md,
				max_width = message_max_width, align = text_align),
			skald.text(entry.sent_time, time_fg, theme.font.size_xs, align = .End),
			spacing = theme.spacing.xs,
			padding = bubble_padding, width = bubble_width,
			bg = bubble_bg, radius = theme.radius.md,
			cross_align = .Stretch)
		if entry.incoming {
			append(&message_nodes, skald.row(
				bubble, skald.flex(1, skald.spacer(0)),
				width = content_width, cross_align = .Start))
		} else {
			append(&message_nodes, skald.row(
				skald.flex(1, skald.spacer(0)), bubble,
				width = content_width, cross_align = .Start))
		}
	}
	if len(message_nodes) == 0 {
		empty_text := "No messages in this conversation."
		if state.selected_peer_id == 0 {
			empty_text = "Select a peer to begin."
		}
		append(&message_nodes, skald.text(empty_text, theme.color.fg_muted, theme.font.size_md))
	}

	can_send := false
	conversation_title := "Conversation"
	if index, found := peer_index(state, state.selected_peer_id); found {
		peer := state.peers[index]
		conversation_title = peer.endpoint
		can_send = state.client_connected && peer.connection == .Online
	}
	header_children := make([dynamic]skald.View, 0, 6, context.temp_allocator)
	if compact {
		append(&header_children, skald.button(ctx, "Peers", Msg(Show_Peers{}),
			id = skald.hash_id("compact-show-peers"), bg = theme.color.surface, fg = theme.color.fg))
	}
	if index, found := peer_index(state, state.selected_peer_id); found {
		append(&header_children, peer_avatar_view(state.peers[index], ctx, 36))
	}
	append(&header_children, skald.text(conversation_title, theme.color.fg, theme.font.size_xl))
	append(&header_children, skald.flex(1, skald.spacer(0)))
	if index, found := peer_index(state, state.selected_peer_id); found {
		peer := state.peers[index]
		if peer.connection == .Online {
			append(&header_children, skald.button(ctx, "Send file", Msg(Open_Transfer_File_Picker{}),
				id = skald.hash_id("conversation-send-file"), bg = theme.color.surface, fg = theme.color.fg))
			append(&header_children, skald.button(ctx, "Disconnect", Disconnect_Peer(peer.id),
				id = skald.hash_id("conversation-disconnect"), bg = theme.color.surface, fg = theme.color.fg))
		} else {
			connect_label := "Connecting…"
			if !state.client_connected {
				connect_label = "Client offline"
			} else if peer.connection == .Disconnected {
				connect_label = "Connect"
			}
			append(&header_children, skald.button(ctx,
				connect_label,
				Connect_Peer(peer.id), id = skald.hash_id("conversation-connect"),
				bg = theme.color.surface, fg = theme.color.fg,
				disabled = !state.client_connected || peer.connection != .Disconnected))
		}
	}
	header := skald.row(..header_children[:], width = content_width, spacing = theme.spacing.sm, cross_align = .Center)
	send_width: f32 = 76
	composer_width := max(f32(0), content_width - send_width - theme.spacing.sm)
	composer_lines := clamp(strings.count(state.message_draft, "\n") + 1, 2, 6)
	composer_height := f32(composer_lines) * (theme.font.size_md + 4) + 2 * theme.spacing.sm
	composer_input := skald.chat_input(ctx, state.message_draft, message_changed, message_submitted,
		id = skald.hash_id("message-composer"),
		placeholder = can_send ? "Write a message… Enter to send, Shift+Enter for a new line" : "Connect to the selected peer to send",
		width = composer_width, min_lines = 2, max_lines = 6, disabled = !can_send)
	send_disabled := !can_send || len(strings.trim_space(state.message_draft)) == 0
	composer := skald.row(
		composer_input,
		skald.button(ctx, "Send", Send_Message(state.message_draft),
			id = skald.hash_id("send-message"), width = send_width, height = composer_height,
			disabled = send_disabled),
		width = content_width, spacing = theme.spacing.sm, cross_align = .End)
	scroll_id := skald.hash_id(fmt.tprintf("conversation-%d", state.selected_peer_id))
	scroll_state := skald.widget_get(ctx, scroll_id, .Scroll)
	scroll_to_end := visible_message_count > scroll_state.reveal_marker
	if visible_message_count != scroll_state.reveal_marker {
		scroll_state.reveal_marker = visible_message_count
		skald.widget_set(ctx, scroll_id, scroll_state)
	}
	timeline := skald.scroll(ctx, {content_width, 0},
		skald.col(..message_nodes[:], spacing = theme.spacing.sm, cross_align = .Stretch),
		id = scroll_id, scroll_to_end = scroll_to_end)

	return skald.col(
		header,
		skald.divider(ctx),
		skald.flex(1, timeline),
		composer,
		width = size.x, height = size.y, spacing = theme.spacing.md, padding = theme.spacing.lg,
		bg = theme.color.bg, cross_align = .Stretch)
}
