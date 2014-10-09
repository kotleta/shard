CONFDIR="/etc/db_b"
LIBDIR="/usr/lib/db_b/lua"
VERSION = 0.003
TIMEOUT = 1

if package and #LIBDIR > 0 then
	package.path = package.path..';'..LIBDIR..'/?.lua'
end

require 'utils'
local log = require 'box.log'

local crc32 = require 'crc32'
local guava = require 'guava'

function hash(key,buckets)
	-- guava return value is in range [0..buckets)
	-- lua indexing is [1..buckets]
	-- so, return guava+1
	return guava(crc32(key),buckets)+1
end

local Servers = {}
Servers.db_b = load_server_list( CONFDIR .. '/db_b-servers.lua' )

local Sharding = require 'box.shard'

Sharding.configure({
	curr_list = Servers.db_b.curr;
	prev_list = Servers.db_b.prev;
	func = function(space, list, key)
		return hash(key,#list)
	end;
})

if store ~= nil then
	store.version = VERSION
else
	store = { version = VERSION };
end
function savedata(uid,...)
	print("savedata : ",uid, " + ", select('#',...))
	local con = box.shard.conns:curr('rw', 0, uid)
	print(uid,": shno = ",shno, "con = ",con)
	local t
	if con then
		if con == box.net.self then
			log.debug("It's me. Just call")
			return _master_savedata(uid,...)
		else
			log.debug("have connection to master. delegate")
			return con:call('_master_savedata',uid, ...)
		end
	else
		log.error("master not accessible: %s", err)
		box.raise(1,"master not accessible: "..err)
	end
end

-- stor:timeout(1):call('savedata',uid,tostring(data.crc or 0),data.sha1 or '',tostring(data.phash or 0),data.lm or 0,data.ctype or '',data.origin or '',data.data1 or '',data.data2 or '',data.data3 or '')

function _master_savedata(uid, crc, sha1, phash, lm, ctype, origin, data1, data2, data3)
	crc   = tonumber(crc)
	phash = tonumber64(phash)
	lm    = tonumber(lm)
	local t = box.select(0,0,uid)
	print('store t: ',t)
	if t then
		return box.update(0,uid,
			'=p=p=p=p=p=p=p=p=p',
			1,crc,
			2,sha1,
			3,phash,
			4,lm,
			5,ctype,
			6,origin,
			7,data1,
			8,data2,
			9,data3
		)
	else
		print(uid," not exists, got to insert")
		return box.insert(0, uid, crc, sha1, phash, lm, ctype, origin, data1, data2, data3)
	end
end


function getdata(uid,size)
	local t = {}
	local res = box.shard.select(0,uid)
	print('store.getdata: ', uid," ",size," ", #res)
	if res and #res > 0 then
		table.insert(t,res[4]) -- lm
		table.insert(t,res[5]) -- ctype
		if size == '32' then
			table.insert(t,res[7]) -- data1 (32)
		elseif size == '90' then
			table.insert(t,res[8]) -- data2 (90)
		elseif size == '180' then
			table.insert(t,res[9]) -- data3 (180)
		else
			error("Size " .. size .. " not had")
		end
	end
	return t
end

function delete(uid)
	box.shard.delete(0,uid)
	return
end
