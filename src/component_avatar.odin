package parior_messenger

import "core:c"
import "core:fmt"
import "core:strings"

import "gui:skald"
import stbi "vendor:stb/image"

MAX_AVATAR_DIMENSION :: 4096
MAX_AVATAR_PIXELS :: 16 * 1024 * 1024
MAX_AVATAR_BYTES :: 1 * 1024 * 1024

avatar_initial :: proc(label: string) -> string {
	if len(label) == 0 {
		return "?"
	}
	first := label[0]
	if first >= 'a' && first <= 'z' {
		first -= 32
	}
	return fmt.tprintf("%c", first)
}

avatar_mime_for_path :: proc(path: string) -> string {
	lower, _ := strings.to_lower(path, context.temp_allocator)
	if strings.has_suffix(lower, ".png") {
		return "image/png"
	}
	if strings.has_suffix(lower, ".jpg") || strings.has_suffix(lower, ".jpeg") {
		return "image/jpeg"
	}
	if strings.has_suffix(lower, ".gif") {
		return "image/gif"
	}
	return ""
}

avatar_dimensions :: proc(data: []u8) -> (width, height: u32, valid: bool) {
	if len(data) == 0 || len(data) > MAX_AVATAR_BYTES || len(data) > int(max(c.int)) {
		return
	}
	w, h, channels: c.int
	if stbi.info_from_memory(raw_data(data), c.int(len(data)), &w, &h, &channels) == 0 || w <= 0 || h <= 0 {
		return
	}
	if w > MAX_AVATAR_DIMENSION || h > MAX_AVATAR_DIMENSION || i64(w) * i64(h) > MAX_AVATAR_PIXELS {
		return
	}
	return u32(w), u32(h), true
}

avatar_data_valid :: proc(data: []u8) -> bool {
	_, _, valid := avatar_dimensions(data)
	return valid
}

peer_avatar_view :: proc(peer: Peer_Row, ctx: ^skald.Ctx(Msg), size: f32) -> skald.View {
	if len(peer.avatar_data) > 0 && len(peer.avatar_hash) > 0 && ctx.renderer != nil {
		key := fmt.tprintf("parior://peer-avatar/%d/%s", peer.id, peer.avatar_hash)
		resident := skald.image_is_resident(ctx.renderer, key)
		if !resident {
			if width, height, valid := avatar_dimensions(peer.avatar_data); valid {
				w, h, channels: c.int
				pixels := stbi.load_from_memory(raw_data(peer.avatar_data), c.int(len(peer.avatar_data)), &w, &h, &channels, 4)
				if pixels != nil {
					rgba := pixels[:int(width * height * 4)]
					resident = skald.image_load_pixels(ctx.renderer, key, width, height, rgba)
					stbi.image_free(pixels)
				}
			}
		}
		if resident {
			return skald.image(ctx, key, width = size, height = size, radius = size / 2)
		}
	}
	return skald.avatar(ctx, avatar_initial(peer.endpoint), size = size)
}
