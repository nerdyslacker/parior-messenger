package parior_messenger

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "core:time/timezone"

import "barev:barev"
import "gui:skald"

POLL_SECONDS :: f32(1.0 / 60.0)

Peer_Row :: struct {
	id:         u64,
	endpoint:   string,
	connection: barev.Connection_State,
	presence:   barev.Presence,
	status:     string,
	avatar_hash: string,
	avatar_mime: string,
	avatar_data: []u8,
	pinned:      bool,
	typing:     bool,
	unread:     int,
}

Conversation_Entry :: struct {
	peer_id:  u64,
	incoming: bool,
	text:     string,
	sent_time: string,
}

State :: struct {
	client:           ^barev.Client,
	polling:          bool,
	peers:            [dynamic]Peer_Row,
	messages:         [dynamic]Conversation_Entry,
	transfers:        [dynamic]Transfer_Row,
	selected_peer_id: u64,
	transfer_dialog_id: u64,
	pending_destination_transfer_id: u64,
	transfer_conflict_id: u64,
	transfer_conflict_path: string,
	endpoint_draft:   string,
	message_draft:    string,
	notice:           string,
	toast_visible:    bool,
	toast_kind:       skald.Toast_Kind,
	toast_revision:   u64,
	dark_theme:       bool,
	client_connected: bool,
	local_presence:   barev.Presence,
	local_avatar_path: string,
	avatar_pending_path: string,
	avatar_busy:      bool,
	pins_dirty:       bool,
	onboarding:       bool,
	nickname_draft:   string,
	bind_draft:       string,
	port_draft:       string,
	compact_show_sidebar: bool,
	add_peer_open:        bool,
	context_peer_id:      u64,
	remove_peer_open:     bool,
	remove_peer_id:       u64,
	pending_remove_peer_id: u64,
}

Poll_Start :: struct {}
Poll_Tick :: struct {}
Endpoint_Changed :: distinct string
Add_Peer :: struct {}
Select_Peer :: distinct u64
Connect_Peer :: distinct u64
Disconnect_Peer :: distinct u64
Message_Changed :: distinct string
Send_Message :: distinct string
Theme_Toggled :: distinct bool
Presence_Changed :: distinct barev.Presence
Disconnect_Self :: struct {}
Connect_Self :: struct {}
Open_Avatar_Picker :: struct {}
Avatar_File_Chosen :: distinct string
Avatar_Picker_Cancelled :: struct {}
Avatar_File_Loaded :: struct {
	data: []u8,
	ok:   bool,
}
Nickname_Changed :: distinct string
Bind_Changed :: distinct string
Port_Changed :: distinct string
Complete_Onboarding :: struct {}
Config_Saved :: distinct bool
Pins_Saved :: distinct bool
Show_Peers :: struct {}
Open_Add_Peer :: struct {}
Cancel_Add_Peer :: struct {}
Peer_Context :: distinct u64
Peer_Menu_Action :: distinct int
Cancel_Remove_Peer :: struct {}
Confirm_Remove_Peer :: struct {}
Toast_Closed :: struct {}
Open_Transfer_File_Picker :: struct {}
Transfer_File_Chosen :: distinct string
Transfer_File_Picker_Cancelled :: struct {}
Choose_Transfer_Destination :: distinct u64
Transfer_Destination_Chosen :: distinct string
Transfer_Destination_Cancelled :: struct {}
Reject_Transfer :: distinct u64
Cancel_Transfer :: distinct u64
Dismiss_Transfer_Dialog :: struct {}
Desktop_Notification_Done :: distinct bool
Open_Transfer_File :: distinct u64
Open_Transfer_Destination :: distinct u64
Transfer_Path_Opened :: struct {
	destination: bool,
	ok:          bool,
}
Rename_Transfer :: distinct u64
Transfer_Rename_Chosen :: distinct string
Transfer_Rename_Cancelled :: struct {}
Overwrite_Transfer :: distinct u64

Msg :: union {
	Poll_Start,
	Poll_Tick,
	Endpoint_Changed,
	Add_Peer,
	Select_Peer,
	Connect_Peer,
	Disconnect_Peer,
	Message_Changed,
	Send_Message,
	Theme_Toggled,
	Presence_Changed,
	Disconnect_Self,
	Connect_Self,
	Open_Avatar_Picker,
	Avatar_File_Chosen,
	Avatar_Picker_Cancelled,
	Avatar_File_Loaded,
	Nickname_Changed,
	Bind_Changed,
	Port_Changed,
	Complete_Onboarding,
	Config_Saved,
	Pins_Saved,
	Show_Peers,
	Open_Add_Peer,
	Cancel_Add_Peer,
	Peer_Context,
	Peer_Menu_Action,
	Cancel_Remove_Peer,
	Confirm_Remove_Peer,
	Toast_Closed,
	Open_Transfer_File_Picker,
	Transfer_File_Chosen,
	Transfer_File_Picker_Cancelled,
	Choose_Transfer_Destination,
	Transfer_Destination_Chosen,
	Transfer_Destination_Cancelled,
	Reject_Transfer,
	Cancel_Transfer,
	Dismiss_Transfer_Dialog,
	Desktop_Notification_Done,
	Open_Transfer_File,
	Open_Transfer_Destination,
	Transfer_Path_Opened,
	Rename_Transfer,
	Transfer_Rename_Chosen,
	Transfer_Rename_Cancelled,
	Overwrite_Transfer,
}

remove_peer :: proc(state: ^State, peer_id: u64) -> (remove_result, save_result: barev.Error) {
	index, found := peer_index(state^, peer_id)
	if !found {
		return .Unknown_Peer, .None
	}
	if result := barev.client_remove_peer(state.client, peer_id); result != .None {
		return result, .None
	}
	was_pinned := state.peers[index].pinned
	delete(state.peers[index].endpoint)
	delete(state.peers[index].status)
	delete(state.peers[index].avatar_hash)
	delete(state.peers[index].avatar_mime)
	delete(state.peers[index].avatar_data)
	ordered_remove(&state.peers, index)
	message_index := 0
	for message_index < len(state.messages) {
		if state.messages[message_index].peer_id == peer_id {
			delete(state.messages[message_index].text)
			delete(state.messages[message_index].sent_time)
			ordered_remove(&state.messages, message_index)
		} else {
			message_index += 1
		}
	}
	if state.selected_peer_id == peer_id {
		state.selected_peer_id = 0
		state.compact_show_sidebar = true
	}
	destroy_transfers_for_peer(state, peer_id)
	if was_pinned {
		state.pins_dirty = true
	}
	state.pending_remove_peer_id = 0
	return .None, barev.client_save_contacts(state.client^, active_contacts_path)
}

set_remove_notice :: proc(state: ^State, remove_result, save_result: barev.Error) {
	if remove_result != .None {
		set_notice(state, fmt.tprintf("Could not remove peer: %v", remove_result))
	} else if save_result != .None {
		set_notice(state, fmt.tprintf("Peer removed, but contacts could not be saved: %v", save_result))
	} else {
		set_notice(state, "Peer removed")
	}
}

sync_peers_from_client :: proc(state: ^State) {
	if !active_client_initialized {
		return
	}
	for ordinal in 0 ..< barev.client_peer_count(state.client^) {
		peer, ok := barev.client_peer_at(state.client, ordinal)
		if !ok {
			continue
		}
		endpoint := barev.format_endpoint(peer.endpoint, include_default_port=true, allocator=context.temp_allocator)
		append(&state.peers, Peer_Row {
			id = peer.id,
			endpoint = strings.clone(endpoint),
			connection = peer.connection,
			presence = peer.presence,
			status = strings.clone(peer.status_text),
			avatar_hash = strings.clone(peer.avatar_hash),
			avatar_mime = strings.clone(peer.avatar_mime),
			avatar_data = clone_bytes(peer.avatar_data),
		})
	}
}

connect_disconnected_peers :: proc(state: ^State) -> int {
	if !state.client_connected || state.client == nil {
		return 0
	}
	connecting := 0
	for &peer in state.peers {
		if peer.connection != .Disconnected {
			continue
		}
		if result := barev.client_connect(state.client, peer.id); result == .None {
			peer.connection = .Connecting
			connecting += 1
		}
	}
	return connecting
}

load_pins :: proc(state: ^State) {
	data, err := os.read_entire_file(active_pins_path, context.allocator)
	if err != nil {
		return
	}
	defer delete(data)
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		endpoint := strings.trim_space(line)
		if len(endpoint) == 0 {
			continue
		}
		for &peer in state.peers {
			if peer.endpoint == endpoint {
				peer.pinned = true
				break
			}
		}
	}
}

format_pins :: proc(state: State, allocator := context.allocator) -> string {
	builder := strings.builder_make(context.temp_allocator)
	defer strings.builder_destroy(&builder)
	for peer in state.peers {
		if peer.pinned {
			strings.write_string(&builder, peer.endpoint)
			strings.write_byte(&builder, '\n')
		}
	}
	return strings.clone(strings.to_string(builder), allocator)
}

init :: proc() -> State {
	state := State {
		client = active_client,
		peers = make([dynamic]Peer_Row),
		messages = make([dynamic]Conversation_Entry),
		transfers = make([dynamic]Transfer_Row),
		endpoint_draft = strings.clone(""),
		message_draft = strings.clone(""),
		transfer_conflict_path = strings.clone(""),
		notice = strings.clone(startup_error),
		toast_visible = len(startup_error) > 0,
		toast_kind = .Danger,
		toast_revision = 1,
		dark_theme = startup_config.dark_theme,
		client_connected = active_client_started,
		local_presence = .Available,
		local_avatar_path = strings.clone(startup_avatar_loaded ? startup_config.avatar_path : ""),
		avatar_pending_path = strings.clone(""),
		onboarding = startup_needs_onboarding,
		nickname_draft = strings.clone(startup_config.nickname),
		bind_draft = strings.clone(startup_config.bind_address),
		port_draft = fmt.aprintf("%d", startup_config.port),
	}
	sync_peers_from_client(&state)
	load_pins(&state)
	_ = connect_disconnected_peers(&state)
	return state
}

set_notice :: proc(state: ^State, value: string) {
	delete(state.notice)
	state.notice = strings.clone(value)
	state.toast_visible = true
	state.toast_revision += 1
	state.toast_kind = .Info
	if strings.has_prefix(value, "Could not") ||
	   strings.has_prefix(value, "Barev error") ||
	   strings.contains(value, "error") ||
	   strings.contains(value, "could not") ||
	   strings.has_prefix(value, "Enter ") ||
	   strings.has_prefix(value, "Choose ") {
		state.toast_kind = .Danger
	} else if strings.has_prefix(value, "Peer added") ||
	          strings.has_prefix(value, "Peer removed") ||
	          strings.has_prefix(value, "Status changed") ||
	          strings.has_prefix(value, "Avatar updated") ||
	          strings.has_prefix(value, "Profile saved") ||
	          strings.has_prefix(value, "Peer pinned") ||
	          strings.has_prefix(value, "Peer unpinned") {
		state.toast_kind = .Success
	}
}

format_message_time :: proc(value: time.Time) -> string {
	datetime, ok := time.time_to_datetime(value)
	if !ok {
		return strings.clone("")
	}
	if region, loaded := timezone.region_load("local", context.temp_allocator); loaded {
		if local_datetime, converted := timezone.datetime_to_tz(datetime, region); converted {
			datetime = local_datetime
		}
	}
	return fmt.aprintf("%02d:%02d", datetime.hour, datetime.minute)
}

replace_string :: proc(destination: ^string, value: string) {
	delete(destination^)
	destination^ = strings.clone(value)
}

clone_bytes :: proc(value: []u8) -> []u8 {
	if len(value) == 0 {
		return nil
	}
	result := make([]u8, len(value))
	copy(result, value)
	return result
}

peer_index :: proc(state: State, id: u64) -> (int, bool) {
	for peer, index in state.peers {
		if peer.id == id {
			return index, true
		}
	}
	return 0, false
}

reduce_barev_events :: proc(state: ^State, notifications: ^[dynamic]Desktop_Notification) {
	for {
		event, ok := barev.client_poll_event(state.client)
		if !ok {
			break
		}

		switch event.kind {
		case .Connected:
			if index, found := peer_index(state^, event.peer_id); found {
				state.peers[index].connection = .Online
			}
		case .Disconnected:
			if index, found := peer_index(state^, event.peer_id); found {
				state.peers[index].connection = .Disconnected
				state.peers[index].presence = .Offline
			}
			if state.pending_remove_peer_id == event.peer_id {
				remove_result, save_result := remove_peer(state, event.peer_id)
				set_remove_notice(state, remove_result, save_result)
			}
		case .Message:
			append(&state.messages, Conversation_Entry {
				peer_id = event.peer_id,
				incoming = true,
				text = strings.clone(event.text),
				sent_time = format_message_time(event.timestamp),
			})
			if event.peer_id != state.selected_peer_id {
				if index, found := peer_index(state^, event.peer_id); found {
					state.peers[index].unread += 1
					append(notifications, desktop_notification(state.peers[index].endpoint, event.text))
				}
			}
		case .Presence:
			if index, found := peer_index(state^, event.peer_id); found {
				state.peers[index].presence = event.presence
				replace_string(&state.peers[index].status, event.text)
			}
		case .Chat_State:
			if index, found := peer_index(state^, event.peer_id); found {
				state.peers[index].typing = event.chat_state == .Composing
			}
		case .Error:
			if event.error == .Transport && event.peer_id != state.selected_peer_id {
				// Background startup/reconnect attempts should update peer state
				// without interrupting the user before a conversation is open.
			} else if index, found := peer_index(state^, event.peer_id); found && event.error == .Transport {
				set_notice(state, fmt.tprintf(
					"Could not reach %s. Check that the peer is running and its endpoint matches.",
					state.peers[index].endpoint))
			} else {
				set_notice(state, fmt.tprintf("Barev error: %v", event.error))
			}
		case .Transfer_Offered:
			if sync_transfer_from_client(state, event.transfer_id) {
				queue_transfer_dialog(state, event.transfer_id)
				if event.peer_id != state.selected_peer_id {
					peer_name := transfer_peer_name(state^, event.peer_id)
					body := fmt.tprintf("%s (%s)", event.text, format_file_size(event.size))
					append(notifications, desktop_notification(
						fmt.tprintf("File offer from %s", peer_name), body))
				}
			}
		case .Transfer_Accepted, .Transfer_Progress:
			_ = sync_transfer_from_client(state, event.transfer_id)
			queue_transfer_dialog(state, event.transfer_id)
		case .Transfer_Completed:
			_ = sync_transfer_from_client(state, event.transfer_id)
			queue_transfer_dialog(state, event.transfer_id)
			set_notice(state, "File transfer completed")
		case .Transfer_Rejected, .Transfer_Cancelled:
			_ = sync_transfer_from_client(state, event.transfer_id)
			queue_transfer_dialog(state, event.transfer_id)
		case .Transfer_Failed:
			_ = sync_transfer_from_client(state, event.transfer_id, event.error)
			queue_transfer_dialog(state, event.transfer_id)
		case .Avatar_Update, .Avatar, .Log:
			if event.kind == .Avatar_Update {
				if index, found := peer_index(state^, event.peer_id); found && state.peers[index].avatar_hash != event.text {
					replace_string(&state.peers[index].avatar_hash, event.text)
					delete(state.peers[index].avatar_mime)
					state.peers[index].avatar_mime = ""
					delete(state.peers[index].avatar_data)
					state.peers[index].avatar_data = nil
				}
			} else if event.kind == .Avatar {
				if index, found := peer_index(state^, event.peer_id); found {
					peer, ok := barev.client_get_peer(state.client, event.peer_id)
					if ok {
						replace_string(&state.peers[index].avatar_hash, peer.avatar_hash)
					}
					replace_string(&state.peers[index].avatar_mime, event.mime)
					delete(state.peers[index].avatar_data)
					state.peers[index].avatar_data = clone_bytes(event.data)
				}
			}
		}

		barev.destroy_event(&event)
	}
}

poll_client :: proc(state: ^State, notifications: ^[dynamic]Desktop_Notification) {
	if state.client == nil || !active_client_started {
		return
	}
	if result := barev.client_process(state.client); result != .None {
		set_notice(state, fmt.tprintf("Barev processing error: %v", result))
	}
	reduce_barev_events(state, notifications)
}

update :: proc(state: State, msg: Msg) -> (State, skald.Command(Msg)) {
	out := state
	switch value in msg {
	case Poll_Start:
		out.polling = true
		return out, skald.cmd_delay(POLL_SECONDS, Msg(Poll_Tick{}))
	case Poll_Tick:
		notifications := make([dynamic]Desktop_Notification, context.temp_allocator)
		poll_client(&out, &notifications)
		commands := make([dynamic]skald.Command(Msg), 0, len(notifications) + 2, context.temp_allocator)
		if out.polling {
			append(&commands, skald.cmd_delay(POLL_SECONDS, Msg(Poll_Tick{})))
		}
		if out.pins_dirty {
			out.pins_dirty = false
			contents := format_pins(out, context.temp_allocator)
			append(&commands, skald.cmd_write_file(active_pins_path, transmute([]u8)contents, pins_saved))
		}
		for notification in notifications {
			append(&commands, desktop_notification_command(notification))
		}
		if len(commands) == 1 {
			return out, commands[0]
		} else if len(commands) > 1 {
			return out, skald.cmd_batch(commands[0], ..commands[1:])
		}
	case Endpoint_Changed:
		replace_string(&out.endpoint_draft, string(value))
	case Add_Peer:
		endpoint := strings.trim_space(out.endpoint_draft)
		if len(endpoint) == 0 {
			set_notice(&out, "Enter a peer endpoint")
			break
		}
		peer_id, result := barev.client_add_peer(out.client, endpoint)
		if result != .None {
			set_notice(&out, fmt.tprintf("Could not add peer: %v", result))
			break
		}
		display_endpoint := endpoint
		if peer, ok := barev.client_get_peer(out.client, peer_id); ok {
			display_endpoint = barev.format_endpoint(peer.endpoint,
				include_default_port = true, allocator = context.temp_allocator)
		}
		append(&out.peers, Peer_Row {
			id = peer_id,
			endpoint = strings.clone(display_endpoint),
			connection = .Disconnected,
			presence = .Offline,
			status = strings.clone(""),
		})
		out.selected_peer_id = peer_id
		out.compact_show_sidebar = false
		out.add_peer_open = false
		replace_string(&out.endpoint_draft, "")
		if !out.client_connected {
			set_notice(&out, "Peer added; connect your profile to reach it")
		} else if connect_result := barev.client_connect(out.client, peer_id); connect_result == .None {
			out.peers[len(out.peers) - 1].connection = .Connecting
			set_notice(&out, "Peer added")
		} else {
			set_notice(&out, fmt.tprintf("Peer added, but could not connect: %v", connect_result))
		}
		if result := barev.client_save_contacts(out.client^, active_contacts_path); result != .None {
			set_notice(&out, fmt.tprintf("Peer added, but contacts could not be saved: %v", result))
		}
	case Select_Peer:
		out.selected_peer_id = u64(value)
		out.compact_show_sidebar = false
		if index, found := peer_index(out, out.selected_peer_id); found {
			out.peers[index].unread = 0
			if out.client_connected && out.peers[index].connection == .Disconnected {
				if result := barev.client_connect(out.client, out.selected_peer_id); result != .None {
					set_notice(&out, fmt.tprintf("Could not connect: %v", result))
				} else {
					out.peers[index].connection = .Connecting
				}
			}
		}
	case Connect_Peer:
		if !out.client_connected {
			set_notice(&out, "Connect your profile before connecting to a peer")
			break
		}
		peer_id := u64(value)
		result := barev.client_connect(out.client, peer_id)
		if result != .None {
			set_notice(&out, fmt.tprintf("Could not connect: %v", result))
		} else if index, found := peer_index(out, peer_id); found {
			out.peers[index].connection = .Connecting
		}
	case Disconnect_Peer:
		if result := barev.client_disconnect(out.client, u64(value)); result != .None {
			set_notice(&out, fmt.tprintf("Could not disconnect: %v", result))
		}
	case Message_Changed:
		replace_string(&out.message_draft, string(value))
		if index, found := peer_index(out, out.selected_peer_id); found && out.peers[index].connection == .Online {
			chat_state: barev.Chat_State = .Composing
			if len(strings.trim_space(string(value))) == 0 {
				chat_state = .Paused
			}
			_ = barev.client_send_chat_state(out.client, out.selected_peer_id, chat_state)
		}
	case Send_Message:
		message := strings.trim_space(string(value))
		if out.selected_peer_id == 0 || len(message) == 0 {
			break
		}
		result := barev.client_send_message(out.client, out.selected_peer_id, message)
		if result != .None {
			set_notice(&out, fmt.tprintf("Could not send message: %v", result))
			break
		}
		append(&out.messages, Conversation_Entry {
			peer_id = out.selected_peer_id,
			text = strings.clone(message),
			sent_time = format_message_time(time.now()),
		})
		replace_string(&out.message_draft, "")
		_ = barev.client_send_chat_state(out.client, out.selected_peer_id, .Active)
	case Theme_Toggled:
		out.dark_theme = bool(value)
		config := App_Config {
			nickname = out.nickname_draft,
			bind_address = out.bind_draft,
			avatar_path = out.local_avatar_path,
			port = startup_config.port,
			dark_theme = out.dark_theme,
		}
		if parsed, ok := strconv.parse_u64(out.port_draft); ok && parsed > 0 && parsed <= u64(max(u16)) {
			config.port = u16(parsed)
		}
		contents := format_config(config, context.temp_allocator)
		return out, skald.cmd_batch(
			skald.cmd_set_theme(Msg, out.dark_theme ? skald.theme_dark() : skald.theme_light()),
			skald.cmd_write_file(active_config_path, transmute([]u8)contents, config_saved),
		)
	case Presence_Changed:
		presence := barev.Presence(value)
		if result := barev.client_set_presence(out.client, presence); result != .None {
			set_notice(&out, fmt.tprintf("Could not change status: %v", result))
		} else {
			out.local_presence = presence
			set_notice(&out, fmt.tprintf("Status changed to %s", presence_label(presence)))
		}
	case Disconnect_Self:
		if active_client_started {
			barev.client_stop(out.client)
			active_client_started = false
		}
		out.client_connected = false
		out.pending_remove_peer_id = 0
		for &peer in out.peers {
			peer.connection = .Disconnected
			peer.presence = .Offline
			peer.typing = false
		}
	case Connect_Self:
		if result := barev.client_start(out.client); result != .None {
			set_notice(&out, fmt.tprintf("Could not connect Barev: %v", result))
			break
		}
		active_client_started = true
		out.client_connected = true
		_ = connect_disconnected_peers(&out)
	case Open_Avatar_Picker:
		if !out.avatar_busy {
			out.avatar_busy = true
			return out, skald.cmd_open_file_dialog(AVATAR_FILTERS, avatar_dialog_result)
		}
	case Avatar_File_Chosen:
		delete(out.avatar_pending_path)
		out.avatar_pending_path = string(value)
		return out, skald.cmd_read_file(out.avatar_pending_path, avatar_file_loaded)
	case Avatar_Picker_Cancelled:
		out.avatar_busy = false
	case Avatar_File_Loaded:
		out.avatar_busy = false
		defer delete(value.data)
		if !value.ok {
			set_notice(&out, "Could not read avatar image")
			delete(out.avatar_pending_path)
			out.avatar_pending_path = strings.clone("")
			break
		}
		mime := avatar_mime_for_path(out.avatar_pending_path)
		if len(mime) == 0 || !avatar_data_valid(value.data) {
			set_notice(&out, "Choose a PNG, JPEG, or GIF up to 1 MB and 4096 × 4096")
			delete(out.avatar_pending_path)
			out.avatar_pending_path = strings.clone("")
			break
		}
		if result := barev.client_set_avatar(out.client, value.data, mime); result != .None {
			set_notice(&out, fmt.tprintf("Could not set avatar: %v", result))
			delete(out.avatar_pending_path)
			out.avatar_pending_path = strings.clone("")
			break
		}
		replace_string(&out.local_avatar_path, out.avatar_pending_path)
		delete(out.avatar_pending_path)
		out.avatar_pending_path = strings.clone("")
		startup_avatar_loaded = true
		set_notice(&out, "Avatar updated")
		avatar_config := App_Config {
			nickname = out.nickname_draft,
			bind_address = out.bind_draft,
			avatar_path = out.local_avatar_path,
			port = startup_config.port,
			dark_theme = out.dark_theme,
		}
		if parsed, ok := strconv.parse_u64(out.port_draft); ok && parsed > 0 && parsed <= u64(max(u16)) {
			avatar_config.port = u16(parsed)
		}
		contents := format_config(avatar_config, context.temp_allocator)
		return out, skald.cmd_write_file(active_config_path, transmute([]u8)contents, config_saved)
	case Nickname_Changed:
		replace_string(&out.nickname_draft, string(value))
	case Bind_Changed:
		replace_string(&out.bind_draft, string(value))
	case Port_Changed:
		replace_string(&out.port_draft, string(value))
	case Complete_Onboarding:
		nickname := strings.trim_space(out.nickname_draft)
		bind_address := strings.trim_space(out.bind_draft)
		parsed_port, port_ok := strconv.parse_u64(strings.trim_space(out.port_draft))
		if len(nickname) == 0 || len(bind_address) == 0 || !port_ok || parsed_port == 0 || parsed_port > u64(max(u16)) {
			set_notice(&out, "Enter a nickname, IPv6 address, and valid port")
			break
		}
		config := App_Config {
			nickname = nickname,
			bind_address = bind_address,
			avatar_path = out.local_avatar_path,
			port = u16(parsed_port),
			dark_theme = out.dark_theme,
		}
		if result := start_active_client(config); result != .None {
			set_notice(&out, fmt.tprintf("Could not start Barev: %v", result))
			break
		}
		startup_needs_onboarding = false
		out.onboarding = false
		out.client_connected = true
		sync_peers_from_client(&out)
		_ = connect_disconnected_peers(&out)
		set_notice(&out, "Profile saved")
		contents := format_config(config, context.temp_allocator)
		return out, skald.cmd_write_file(active_config_path, transmute([]u8)contents, config_saved)
	case Config_Saved:
		if !bool(value) {
			set_notice(&out, "Could not save local settings")
		}
	case Pins_Saved:
		if !bool(value) {
			set_notice(&out, "Could not save pinned peers")
		}
	case Show_Peers:
		out.compact_show_sidebar = true
	case Open_Add_Peer:
		out.add_peer_open = true
	case Cancel_Add_Peer:
		out.add_peer_open = false
	case Peer_Context:
		out.context_peer_id = u64(value)
	case Peer_Menu_Action:
		switch int(value) {
		case 0: // Pin or unpin
			if index, found := peer_index(out, out.context_peer_id); found {
				out.peers[index].pinned = !out.peers[index].pinned
				out.pins_dirty = true
				set_notice(&out, out.peers[index].pinned ? "Peer pinned" : "Peer unpinned")
			}
		case 1: // Remove
			if _, found := peer_index(out, out.context_peer_id); found {
				out.remove_peer_id = out.context_peer_id
				out.remove_peer_open = true
			}
		}
	case Cancel_Remove_Peer:
		out.remove_peer_open = false
		out.remove_peer_id = 0
	case Confirm_Remove_Peer:
		peer_id := out.remove_peer_id
		out.remove_peer_open = false
		out.remove_peer_id = 0
		if index, found := peer_index(out, peer_id); found && out.peers[index].connection != .Disconnected {
			if result := barev.client_disconnect(out.client, peer_id); result != .None {
				set_notice(&out, fmt.tprintf("Could not disconnect peer for removal: %v", result))
			} else {
				out.pending_remove_peer_id = peer_id
				out.peers[index].connection = .Closing
				set_notice(&out, "Disconnecting peer before removal…")
			}
		} else {
			remove_result, save_result := remove_peer(&out, peer_id)
			set_remove_notice(&out, remove_result, save_result)
		}
	case Toast_Closed:
		out.toast_visible = false
	case Open_Transfer_File_Picker:
		if index, found := peer_index(out, out.selected_peer_id); !found || out.peers[index].connection != .Online {
			set_notice(&out, "Connect to a peer before sending a file")
		} else {
			return out, skald.cmd_open_file_dialog(nil, outgoing_file_chosen)
		}
	case Transfer_File_Chosen:
		path := string(value)
		defer delete(path)
		transfer_id, result := barev.client_offer_file(out.client, out.selected_peer_id, path)
		if result != .None {
			set_notice(&out, fmt.tprintf("Could not offer file: %v", result))
		} else if sync_transfer_from_client(&out, transfer_id) {
			out.transfer_dialog_id = transfer_id
		}
	case Transfer_File_Picker_Cancelled:
	case Choose_Transfer_Destination:
		out.pending_destination_transfer_id = u64(value)
		return out, skald.cmd_open_folder_dialog(transfer_destination_chosen)
	case Transfer_Destination_Chosen:
		directory := string(value)
		defer delete(directory)
		transfer_id := out.pending_destination_transfer_id
		out.pending_destination_transfer_id = 0
		if result := barev.client_accept_file(out.client, transfer_id, directory); result == .File_Exists {
			if !set_transfer_conflict(&out, transfer_id, directory) {
				set_notice(&out, "Could not prepare file conflict options")
			}
		} else if result != .None {
			set_notice(&out, fmt.tprintf("Could not accept file: %v", result))
		} else {
			clear_transfer_conflict(&out, transfer_id)
			_ = sync_transfer_from_client(&out, transfer_id)
			out.transfer_dialog_id = transfer_id
		}
	case Transfer_Destination_Cancelled:
		out.pending_destination_transfer_id = 0
	case Reject_Transfer:
		transfer_id := u64(value)
		if result := barev.client_reject_file(out.client, transfer_id); result != .None {
			set_notice(&out, fmt.tprintf("Could not reject file: %v", result))
		} else {
			clear_transfer_conflict(&out, transfer_id)
			_ = sync_transfer_from_client(&out, transfer_id)
			out.transfer_dialog_id = transfer_id
		}
	case Cancel_Transfer:
		transfer_id := u64(value)
		if result := barev.client_cancel_transfer(out.client, transfer_id); result != .None {
			set_notice(&out, fmt.tprintf("Could not cancel transfer: %v", result))
		} else {
			_ = sync_transfer_from_client(&out, transfer_id)
			out.transfer_dialog_id = transfer_id
		}
	case Dismiss_Transfer_Dialog:
		if index, found := transfer_index(out, out.transfer_dialog_id); found {
			out.transfers[index].dialog_dismissed = true
			transfer := out.transfers[index]
			if transfer.direction == .Incoming && transfer.state == .Offered {
				if result := barev.client_reject_file(out.client, transfer.id); result != .None {
					set_notice(&out, fmt.tprintf("Could not reject file: %v", result))
					break
				}
				_ = sync_transfer_from_client(&out, transfer.id)
			} else if transfer.state == .Offered || transfer.state == .Accepted || transfer.state == .Transferring {
				if result := barev.client_cancel_transfer(out.client, transfer.id); result != .None {
					set_notice(&out, fmt.tprintf("Could not cancel transfer: %v", result))
					break
				}
				_ = sync_transfer_from_client(&out, transfer.id)
			}
			clear_transfer_conflict(&out, transfer.id)
		}
		out.transfer_dialog_id = 0
		activate_next_transfer_offer(&out)
	case Desktop_Notification_Done:
	case Open_Transfer_File:
		if index, found := transfer_index(out, u64(value)); found {
			return out, transfer_path_command(out.transfers[index], false)
		}
	case Open_Transfer_Destination:
		if index, found := transfer_index(out, u64(value)); found {
			return out, transfer_path_command(out.transfers[index], true)
		}
	case Transfer_Path_Opened:
		if !value.ok {
			set_notice(&out, value.destination ? "Could not open file destination" : "Could not open transferred file")
		}
	case Rename_Transfer:
		transfer_id := u64(value)
		out.pending_destination_transfer_id = transfer_id
		return out, transfer_rename_command(out, transfer_id)
	case Transfer_Rename_Chosen:
		path := string(value)
		defer delete(path)
		transfer_id := out.pending_destination_transfer_id
		out.pending_destination_transfer_id = 0
		if result := barev.client_accept_file_to(out.client, transfer_id, path); result == .File_Exists {
			set_transfer_conflict_path(&out, transfer_id, path)
		} else if result != .None {
			set_notice(&out, fmt.tprintf("Could not save file with the selected name: %v", result))
		} else {
			clear_transfer_conflict(&out, transfer_id)
			_ = sync_transfer_from_client(&out, transfer_id)
			out.transfer_dialog_id = transfer_id
		}
	case Transfer_Rename_Cancelled:
		out.pending_destination_transfer_id = 0
	case Overwrite_Transfer:
		transfer_id := u64(value)
		if transfer_id != out.transfer_conflict_id || len(out.transfer_conflict_path) == 0 {
			set_notice(&out, "Could not find the file to overwrite")
			break
		}
		if result := barev.client_accept_file_to(out.client, transfer_id, out.transfer_conflict_path, true); result != .None {
			set_notice(&out, fmt.tprintf("Could not overwrite file: %v", result))
		} else {
			clear_transfer_conflict(&out, transfer_id)
			_ = sync_transfer_from_client(&out, transfer_id)
			out.transfer_dialog_id = transfer_id
		}
	}
	return out, {}
}

config_saved :: proc(result: skald.File_Write_Result) -> Msg {
	return Config_Saved(result.err == .None)
}

pins_saved :: proc(result: skald.File_Write_Result) -> Msg {
	return Pins_Saved(result.err == .None)
}

responsive_content :: proc(ctx: ^skald.Ctx(Msg), state: ^State, size: [2]f32) -> skald.View {
	if state.onboarding {
		return onboarding_view(state^, ctx, size)
	}
	breakpoint := skald.breakpoint_for_width(size.x)
	if breakpoint == .Compact {
		if state.compact_show_sidebar || state.selected_peer_id == 0 {
			return peer_sidebar(state^, ctx, size)
		}
		return conversation_view(state^, ctx, size, true)
	}

	sidebar_width: f32 = 310
	if breakpoint == .Regular {
		sidebar_width = clamp(size.x * 0.34, 260, 310)
	}
	conversation_width := max(f32(0), size.x - sidebar_width - 1)
	return skald.row(
		peer_sidebar(state^, ctx, {sidebar_width, size.y}),
		skald.divider(ctx, vertical = true),
		conversation_view(state^, ctx, {conversation_width, size.y}, false),
		width = size.x,
		height = size.y,
		cross_align = .Stretch,
	)
}

toast_closed :: proc() -> Msg {
	return Toast_Closed{}
}

responsive_root :: proc(ctx: ^skald.Ctx(Msg), state: ^State, size: [2]f32) -> skald.View {
	content := responsive_content(ctx, state, size)
	toast := skald.toast(ctx,
		state.toast_visible,
		state.notice,
		toast_closed,
		kind = state.toast_kind,
		anchor = .Top_Center,
		id = skald.hash_id(fmt.tprintf("app-toast-%d", state.toast_revision)),
		dismiss_after = 4,
	)
	transfer_dialog := transfer_dialog_view(state^, ctx)
	return skald.col(content, toast, transfer_dialog,
		width = size.x, height = size.y, cross_align = .Stretch)
}

view :: proc(state: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	if !state.polling {
		if !state.onboarding {
			skald.send(ctx, Msg(Poll_Start{}))
		}
	}
	snapshot := state
	return skald.sized(ctx, &snapshot, responsive_root, min_w = 280, min_h = 360)
}

make_app :: proc() -> skald.App(State, Msg) {
	return {
		title = active_window_title,
		size = {1060, 720},
		theme = startup_config.dark_theme ? skald.theme_dark() : skald.theme_light(),
		init = init,
		update = update,
		view = view,
	}
}
