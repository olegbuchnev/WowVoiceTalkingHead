-- Bounded data-only decoding for THR1 exports. Never execute imported Lua.
local Codec = {}
TalkingHeadRuRankingCodec = Codec
local floor, mod = math.floor, 4294967296
local bits = bit or bit32
local function combine(a, b, xor)
    local result, place = 0, 1
    for _ = 1, 32 do
        local x, y = a % 2, b % 2
        if (xor and x ~= y) or (not xor and x == 1 and y == 1) then result = result + place end
        a, b, place = floor(a / 2), floor(b / 2), place * 2
    end
    return result
end
local function band(a, b) return bits and bits.band(a, b) % mod or combine(a, b, false) end
local function bxor(a, b) return bits and bits.bxor(a, b) % mod or combine(a, b, true) end
local function xor3(a, b, c) return bxor(bxor(a, b), c) end
local function rotate(a, n) return floor(a / 2^n) + (a % 2^n) * 2^(32-n) end
local constants = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
function Codec.SHA256(text)
    local length = #text * 8
    local suffix = {}
    for i = 7, 0, -1 do suffix[#suffix+1] = string.char(floor(length / 256^i) % 256) end
    text = text .. string.char(128) .. string.rep('\0', (55-#text) % 64) .. table.concat(suffix)
    local h = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
    for i,value in ipairs(h) do h[i]=value%mod end
    for offset = 1, #text, 64 do
        local w = {}
        for i = 0, 15 do
            local a,b,c,d = text:byte(offset+i*4, offset+i*4+3)
            w[i] = ((a*256.0+b)*256+c)*256+d
        end
        for i = 16, 63 do
            local a,b = w[i-15],w[i-2]
            w[i] = (w[i-16]+xor3(rotate(a,7),rotate(a,18),floor(a/8))+w[i-7]
                +xor3(rotate(b,17),rotate(b,19),floor(b/1024))) % mod
        end
        local a,b,c,d,e,f,g,v = h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8]
        for i = 0, 63 do
            local t1 = (v+xor3(rotate(e,6),rotate(e,11),rotate(e,25))
                +bxor(band(e,f),band(mod-1-e,g))+constants[i+1]+w[i]) % mod
            local t2 = (xor3(rotate(a,2),rotate(a,13),rotate(a,22))
                +xor3(band(a,b),band(a,c),band(b,c))) % mod
            v,g,f,e,d,c,b,a = g,f,e,(d+t1)%mod,c,b,a,(t1+t2)%mod
        end
        for i,value in ipairs({a,b,c,d,e,f,g,v}) do h[i] = (h[i]+value)%mod end
    end
    local hex = {}
    for _,value in ipairs(h) do
        -- Byte formatting also works in Lua hosts whose integer type is signed 32-bit.
        for shift = 3, 0, -1 do hex[#hex+1] = string.format('%02x',floor(value/256^shift)%256) end
    end
    return table.concat(hex)
end

local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
local digits = {}
for i = 1, #alphabet do digits[alphabet:sub(i,i)] = i-1 end
local function base64(text)
    assert(#text%4 ~= 1 and not text:find('[^%w_-]'), 'Invalid Base64url')
    local output, value, count = {}, 0, 0
    for i = 1, #text do
        local digit = digits[text:sub(i,i)]; assert(digit, 'Invalid Base64url')
        value, count = value*64+digit, count+6
        if count >= 8 then
            count = count-8
            output[#output+1] = string.char(floor(value/2^count))
            value = value%2^count
        end
    end
    assert(value == 0, 'Noncanonical Base64url')
    return table.concat(output)
end

Codec.Null = {}
local array, object = {}, {}
function Codec.IsArray(value) return type(value)=='table' and getmetatable(value)==array end
function Codec.IsObject(value) return type(value)=='table' and getmetatable(value)==object end
function Codec.JSON(text)
    assert(type(text)=='string' and #text<=65536, 'JSON exceeds import limit')
    local pos, tokens = 1, 0
    local function whitespace() local _,last = text:find('^[ \t\r\n]*',pos); pos = (last or pos-1)+1 end
    local function utf8(code)
        if code<128 then return string.char(code) end
        if code<2048 then return string.char(192+floor(code/64),128+code%64) end
        if code<65536 then return string.char(224+floor(code/4096),128+floor(code/64)%64,128+code%64) end
        return string.char(240+floor(code/262144),128+floor(code/4096)%64,128+floor(code/64)%64,128+code%64)
    end
    local function hex4()
        local hex = text:sub(pos,pos+3); assert(#hex==4 and hex:match('^%x+$'),'Invalid Unicode escape')
        pos=pos+4; return tonumber(hex,16)
    end
    local function stringValue()
        assert(text:sub(pos,pos)=='"','Expected JSON string'); pos=pos+1
        local result = {}
        while pos<=#text do
            local char=text:sub(pos,pos); pos=pos+1
            if char=='"' then return table.concat(result) end
            assert(char:byte()>=32,'Invalid JSON string')
            if char=='\\' then
                char=text:sub(pos,pos); pos=pos+1
                local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
                if char=='u' then
                    local code=hex4()
                    if code>=0xd800 and code<=0xdbff then
                        assert(text:sub(pos,pos+1)=='\\u','Missing low surrogate'); pos=pos+2
                        local low=hex4(); assert(low>=0xdc00 and low<=0xdfff,'Invalid low surrogate')
                        code=65536+(code-0xd800)*1024+low-0xdc00
                    else assert(code<0xdc00 or code>0xdfff,'Unpaired surrogate') end
                    char=utf8(code)
                else char=escapes[char]; assert(char,'Invalid JSON escape') end
            end
            result[#result+1]=char
        end
        error('Unterminated JSON string')
    end
    local parse
    parse=function(depth)
        tokens=tokens+1; assert(depth<=12 and tokens<=16000,'JSON is too complex')
        whitespace(); local char=text:sub(pos,pos)
        if char=='"' then return stringValue() end
        if char=='{' or char=='[' then
            local isObject=char=='{'; local close=isObject and '}' or ']'
            local value=setmetatable({},isObject and object or array)
            pos=pos+1; whitespace()
            if text:sub(pos,pos)==close then pos=pos+1; return value end
            while true do
                local key=#value+1
                if isObject then
                    whitespace(); key=stringValue(); assert(value[key]==nil,'Duplicate JSON key')
                    whitespace(); assert(text:sub(pos,pos)==':','Expected colon'); pos=pos+1
                end
                value[key]=parse(depth+1); whitespace(); char=text:sub(pos,pos); pos=pos+1
                if char==close then return value end
                assert(char==',','Expected comma')
            end
        end
        for _,entry in ipairs({{'true',true},{'false',false},{'null',Codec.Null}}) do
            if text:sub(pos,pos+#entry[1]-1)==entry[1] then pos=pos+#entry[1]; return entry[2] end
        end
        local number=text:match('^-?%d+%.?%d*[eE]?[+-]?%d*',pos)
        assert(number and (number:match('^-?%d+$') or number:match('^-?%d+%.%d+$')
            or number:match('^-?%d+[eE][+-]?%d+$') or number:match('^-?%d+%.%d+[eE][+-]?%d+$')),'Invalid JSON value')
        assert(not number:match('^-?0%d'),'Leading zero')
        local value=tonumber(number); assert(value and value==value and math.abs(value)<math.huge,'Invalid number')
        pos=pos+#number; return value
    end
    local value=parse(0); whitespace(); assert(pos>#text,'Trailing JSON data'); return value
end

function Codec.Decode(text)
    assert(type(text)=='string' and #text<=87516,'Import exceeds limit')
    text=text:match('^%s*(.-)%s*$'); assert(#text<=87452,'Import exceeds limit')
    local encoded,hash=text:match('^THR1:([%w_-]+)%.([a-f0-9]+)$')
    assert(encoded and #hash==64,'Invalid THR1 string')
    local json=base64(encoded); assert(#json<=65536,'JSON exceeds import limit')
    assert(Codec.SHA256(json)==hash,'Checksum mismatch')
    return Codec.JSON(json),json,hash
end
