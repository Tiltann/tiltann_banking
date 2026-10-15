--- @module shared.sha256
--- Minimal, dependency-free SHA-256 implementation using Lua 5.4's native
--- bitwise operators. Vendored rather than pulled in as an external
--- dependency, per the project's zero-extra-native-dependency decision for
--- PIN hashing (see server/cards/cards.lua), SHA-256 is a public,
--- unpatented algorithm and pure-Lua implementations of it are standard
--- practice across the FiveM ecosystem. Not used for anything beyond
--- hashing a short numeric PIN with a per-card random salt, this is
--- explicitly NOT intended as general-purpose cryptography.

local band, bor, bxor, bnot = function(a, b) return a & b end,
	function(a, b) return a | b end,
	function(a, b) return a ~ b end,
	function(a) return ~a & 0xFFFFFFFF end
local rshift, lshift = function(a, n) return (a >> n) & 0xFFFFFFFF end,
	function(a, n) return (a << n) & 0xFFFFFFFF end

local function rrotate(x, n)
	return bor(rshift(x, n), lshift(x, 32 - n))
end

local k = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

--- Hashes `message` and returns the digest as a 64-character lowercase hex
--- string.
---@param message string
---@return string hexDigest
local function sha256(message)
	local h0, h1, h2, h3, h4, h5, h6, h7 =
		0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
		0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19

	local msgLen = #message
	local bitLen = msgLen * 8

	message = message .. '\128'
	while (#message % 64) ~= 56 do
		message = message .. '\0'
	end

	-- Append the 64-bit big-endian length. Lua integers are 64-bit, so this
	-- is a plain unsigned split rather than needing a separate high/low pair.
	for i = 7, 0, -1 do
		message = message .. string.char(rshift(bitLen, i * 8) & 0xFF)
	end

	for chunkStart = 1, #message, 64 do
		local w = {}

		for i = 0, 15 do
			local offset = chunkStart + i * 4
			local b1, b2, b3, b4 = message:byte(offset, offset + 3)
			w[i] = bor(bor(lshift(b1, 24), lshift(b2, 16)), bor(lshift(b3, 8), b4))
		end

		for i = 16, 63 do
			local s0 = bxor(bxor(rrotate(w[i - 15], 7), rrotate(w[i - 15], 18)), rshift(w[i - 15], 3))
			local s1 = bxor(bxor(rrotate(w[i - 2], 17), rrotate(w[i - 2], 19)), rshift(w[i - 2], 10))
			w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xFFFFFFFF
		end

		local a, b, c, d, e, f, g, hh = h0, h1, h2, h3, h4, h5, h6, h7

		for i = 0, 63 do
			local s1 = bxor(bxor(rrotate(e, 6), rrotate(e, 11)), rrotate(e, 25))
			local ch = bxor(band(e, f), band(bnot(e), g))
			local temp1 = (hh + s1 + ch + k[i + 1] + w[i]) & 0xFFFFFFFF
			local s0 = bxor(bxor(rrotate(a, 2), rrotate(a, 13)), rrotate(a, 22))
			local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
			local temp2 = (s0 + maj) & 0xFFFFFFFF

			hh = g
			g = f
			f = e
			e = (d + temp1) & 0xFFFFFFFF
			d = c
			c = b
			b = a
			a = (temp1 + temp2) & 0xFFFFFFFF
		end

		h0 = (h0 + a) & 0xFFFFFFFF
		h1 = (h1 + b) & 0xFFFFFFFF
		h2 = (h2 + c) & 0xFFFFFFFF
		h3 = (h3 + d) & 0xFFFFFFFF
		h4 = (h4 + e) & 0xFFFFFFFF
		h5 = (h5 + f) & 0xFFFFFFFF
		h6 = (h6 + g) & 0xFFFFFFFF
		h7 = (h7 + hh) & 0xFFFFFFFF
	end

	return ('%08x%08x%08x%08x%08x%08x%08x%08x'):format(h0, h1, h2, h3, h4, h5, h6, h7)
end

TbSha256 = sha256
