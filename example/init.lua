CONFDIR="/etc/db_a"
LIBDIR="/usr/lib/db_a/lua"
VERSION = 0.003
TIMEOUT = 1

if package and #LIBDIR > 0 then
	package.path = package.path..';'..LIBDIR..'/?.lua'
end

require 'utils'
require 'box.connpool'
local log = require 'box.log'

local crc32 = require 'crc32'
local guava = require 'guava'

local condvar = require 'box.cv'

function hash(key,buckets)
	return guava(crc32(key),buckets)+1
end

local Servers = {}
Servers.db_a = load_server_list( CONFDIR .. '/db_a-servers.lua' )
Servers.db_b = load_server_list( CONFDIR .. '/db_b-servers.lua' )

print("Servers: ",box.cjson.encode(Servers.db_a.raw))

local Sharding = require 'box.shard'

Sharding.configure({
	curr_list = Servers.db_a.curr;
	prev_list = Servers.db_a.prev;
	func = function(space, list, key)
		return hash(key,#list)
	end;
})


local db_b = box.connpool( Servers.db_b.list, { name = 'db_b'; timeout = 1 }):connect()


if db_a ~= nil then
	db_a.version = VERSION
else
	db_a = { version = VERSION, stats = { } };
end

db_a.status = box.info().status

r,e = trycall(dofile, CONFDIR .. '/as-conf.lua')
if r then
	db_a.conf = r
else
	print("Error on load config: ", e)
	db_a.conf = { }
end

local uid = 3
local STATUS = 4

function fn() return box.pack('i',math.floor(box.time())) end

local N  = { true,   true,    true, false,  false,   false,   true,  false  }
local FL = { "atime","acnt","rtime","uid","status","service","ctime","meta" }
local DF = { fn,   '\0\0\0\0', fn,    '',     '',      '',       fn,     ''     }
local F  = { }
for k,v in pairs(FL) do
	F[ v ] = (k-1)
end

-- update values on save
local US = {}
for k,v in pairs({"rtime","status","service","meta" }) do
	US[v] = 1;
end

function trycall(f,...)
	local r = { pcall(f,...) }
	if r[1] then
		table.remove(r,1)
		return unpack(r)
	else
		return nil
	end
end

function lookup(uid,size)
	if size == nil then size = '32' end
	t = box.shard.select(0,uid)
	if t and t[F['status']] == 'H' then
		local str = db_b:any()
		if not str then error("Storage not available") end
		local res = str:timeout(TIMEOUT):call('getdata',uid,size)
		if res and #res > 0 then
			-- res[1] - lm
			-- res[2] - ctype
			-- res[4] - data
			local xt = {t:unpack()}
			for i=0,2 do table.insert(xt,res[i]) end
			t = box.tuple.new(xt)
		else
			error("Failed to fetch data from storage")
		end
	elseif t and #t > 0 then
		local xt = {t:unpack()}
		for i=0,2 do table.insert(xt,'') end
		t = box.tuple.new(xt)
	end
	if t and #t > 0 then
		return t
	else
		return
	end
end

function resolve(uid, size)
	if size == nil then size = '32' end
	local con = box.shard.conns:curr('rw', 0, uid)
	local t
	if con then
		if con == box.net.self then
			log.debug("It's me. Just call")
			t = _master_resolve(uid)
		else
			log.debug(uid .. ": have connection to master. delegate")
			t = con:call('_master_resolve',uid)
		end
	else
		printf("%s: master not accessible. just read",uid)
		t = box.shard.select(0,uid)
	end
	if t then
		if t[STATUS] == 'H' then
			local str = db_b:any()
			if not str then error(uid .. ": Storage not available") end
			local res = str:timeout(TIMEOUT):call('getdata',uid,size)
			if res and #res then
				local xt = {t:unpack()}
				for i=0,2 do table.insert(xt,res[i]) end
				t = box.tuple.new(xt)
			else
				error(uid .. ": Failed to fetch data from storage")
			end
			return t
		else
			return t
		end
	else
		return
	end
end


function _master_resolve(uid)
	local t = box.update(0,uid,"=p+p",F['atime'],math.floor(box.time()),F['acnt'],1)
	if t then
		--print(uid,": jast updated")
		return t
	else
		--print(uid,": not exists: insert")
		return box.insert(0, 0,0,0,uid,"R","",math.floor(box.time()),"")
	end
end

function dots2hash(...)
	local r = {}
	local data = {...}
	for i = 1, #data, 2 do
		r[ data[ i ] ] = data[ i + 1 ]
	end
	return r
end

function save(uid, ...)
	local con = box.shard.conns:curr('rw', 0, uid)
	local t
	if con then
		if con == box.net.self then
			log.debug("It's me. Just call")
			t = _master_save(uid,...)
		else
			log.debug(uid .. ": have connection to master. delegate")
			t = con:call('_master_save',uid, ...)
		end
	else
		printf("%s: master not accessible.",uid)
		box.raise(1,"master not accessible");
	end
	if t then
		return t
	else
		return
	end
	
end

function _master_save(uid,...)
	local data = dots2hash(...)
	local t = box.select(0,0,uid)
	local r
	if t then
		if t[F['status']] == 'X' then
			--print("No update, ",uid," is banned.")
			return
		end
		local fm = ''
		local up = {}
		for k,v in pairs(F) do -- v - tuple fieldno: 0 .. max
			if US[k] ~= nil and data[k] ~= nil then
				fm = fm .. '=p'
				table.insert(up,v)
				table.insert(up, N[v+1] and box.pack('i', tonumber(data[k])) or data[k])
			end
		end
		--print(uid,": update = ",fm," -> ",unpack(up))
		if fm ~= '' then r = box.update( 0, uid, fm, unpack(up) ) else r = t end
	else
		local ins = {}
		data["uid"] = uid
		for k,v in pairs(FL) do -- k - tuple fieldno: 1 .. max+1
			if data[v] ~= nil then
				table.insert(ins, N[k] and box.pack('i', tonumber(data[v])) or data[v])
			else
				local val = DF[k]
				if type(DF[k]) == 'function' then
					val = DF[k]()
				end
				table.insert(ins, val)
			end
		end
		--print(uid,": box insert")
		r = box.insert(0,ins)
	end
	if data.data1 and #data.data1 > 0 then
		local str = db_b:any()
		if str then
			str:timeout(1):call('savedata',uid,tostring(data.crc or 0),data.sha1 or '',tostring(data.phash or 0), tostring(data.lm or 0),data.ctype or '',data.origin or '',data.data1 or '',data.data2 or '',data.data3 or '')
		else
			print(uid,": have data, but can't save to db_b")
		end
	end
	return r
end

function disable (uid)
	local str = db_b:any()
	if not str then error("Storage not available") end
	str:timeout(TIMEOUT):call('delete',uid)
	return box.shard.update(0,uid,'=p',F['status'],'X')
end

function delete (uid)
	local str = db_b:any()
	if not str then error("Storage not available") end
	str:timeout(TIMEOUT):call('delete',uid)
	return box.shard.delete(0,uid)
end
function refresh (uid,sv)
	local t = box.shard.select(0,uid);
	local str = db_b:any()
	if not str then error("Storage not available") end
	str:timeout(TIMEOUT):call('delete',uid)
	return box.shard.update(0,uid,'=p=p',F['status'],'R',F['service'],'')
end
