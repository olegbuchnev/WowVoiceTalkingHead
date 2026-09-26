--[[ WowVoice: HMAC-SHA256 using pure arithmetic, without a bit library.

Compute audio filenames as HMAC-SHA256(license_secret, quest), matching
the Python installer. Each license has its own secret, so hashed files
from another license cannot be resolved.

Avoid bit.* because availability varies across WoW 3.3.5a and other builds.
Arithmetic (floor, %, multiplication) works everywhere and matches Python's
hmac.new(...).hexdigest(). Results are computed once per quest and cached,
so hashing performance is not critical.
]]

local floor = math.floor
local MOD = 4294967296          -- 2^32

-- Implement 32-bit bitwise operations using arithmetic.
local function AND(a, b)
    local r, p = 0, 1
    for _ = 1, 32 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a = floor(a / 2); b = floor(b / 2); p = p * 2
    end
    return r
end

local function XOR(a, b)
    local r, p = 0, 1
    for _ = 1, 32 do
        local x, y = a % 2, b % 2
        if x ~= y then r = r + p end
        a = floor(a / 2); b = floor(b / 2); p = p * 2
    end
    return r
end

local function NOT(a) return MOD - 1 - a end
local function RSHIFT(a, n) return floor(a / (2 ^ n)) end
local function ROR(a, n)
    return (RSHIFT(a, n) + (a * (2 ^ (32 - n))) % MOD) % MOD
end

local K = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}

local function be32(w)
    return string.char(floor(w / 16777216) % 256, floor(w / 65536) % 256,
                       floor(w / 256) % 256, w % 256)
end

-- SHA-256 -> a table of eight 32-bit words
local function sha256_words(msg)
    local bitlen = #msg * 8
    msg = msg .. "\128"
    while #msg % 64 ~= 56 do msg = msg .. "\0" end
    msg = msg .. be32(floor(bitlen / MOD)) .. be32(bitlen % MOD)

    local h0,h1,h2,h3 = 0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a
    local h4,h5,h6,h7 = 0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19

    local w = {}
    for i = 1, #msg, 64 do
        for j = 0, 15 do
            local a,b,c,d = msg:byte(i + j*4, i + j*4 + 3)
            w[j] = ((a*256 + b)*256 + c)*256 + d
        end
        for j = 16, 63 do
            local x, y = w[j-15], w[j-2]
            local s0 = XOR(XOR(ROR(x,7), ROR(x,18)), RSHIFT(x,3))
            local s1 = XOR(XOR(ROR(y,17), ROR(y,19)), RSHIFT(y,10))
            w[j] = (w[j-16] + s0 + w[j-7] + s1) % MOD
        end
        local a,b,c,d,e,f,g,h = h0,h1,h2,h3,h4,h5,h6,h7
        for j = 0, 63 do
            local S1 = XOR(XOR(ROR(e,6), ROR(e,11)), ROR(e,25))
            local ch = XOR(AND(e,f), AND(NOT(e), g))
            local t1 = (h + S1 + ch + K[j+1] + w[j]) % MOD
            local S0 = XOR(XOR(ROR(a,2), ROR(a,13)), ROR(a,22))
            local maj = XOR(XOR(AND(a,b), AND(a,c)), AND(b,c))
            local t2 = (S0 + maj) % MOD
            h=g; g=f; f=e; e=(d + t1) % MOD; d=c; c=b; b=a; a=(t1 + t2) % MOD
        end
        h0=(h0+a)%MOD; h1=(h1+b)%MOD; h2=(h2+c)%MOD; h3=(h3+d)%MOD
        h4=(h4+e)%MOD; h5=(h5+f)%MOD; h6=(h6+g)%MOD; h7=(h7+h)%MOD
    end
    return {h0,h1,h2,h3,h4,h5,h6,h7}
end

local function words_to_bytes(t)
    local s = {}
    for i = 1, 8 do s[i] = be32(t[i]) end
    return table.concat(s)
end

local function words_to_hex(t)
    local s = {}
    for i = 1, 8 do s[i] = string.format("%08x", t[i]) end
    return table.concat(s)
end

-- HMAC-SHA256(key, msg) -> a 64-character hexadecimal string
local function hmac_hex(key, msg)
    if #key > 64 then key = words_to_bytes(sha256_words(key)) end
    key = key .. string.rep("\0", 64 - #key)
    local ipad, opad = {}, {}
    for i = 1, 64 do
        local kb = key:byte(i)
        ipad[i] = string.char(XOR(kb, 0x36))
        opad[i] = string.char(XOR(kb, 0x5c))
    end
    local inner = words_to_bytes(sha256_words(table.concat(ipad) .. msg))
    return words_to_hex(sha256_words(table.concat(opad) .. inner))
end

WowVoiceHash = {
    sha256_hex = function(m) return words_to_hex(sha256_words(m)) end,
    hmac_hex = hmac_hex,
    -- Filename for (license secret, quest key "179a") -> "<32 hex>.ogg"
    filename = function(secret, key)
        return string.sub(hmac_hex(secret, key), 1, 32) .. ".ogg"
    end,
}
