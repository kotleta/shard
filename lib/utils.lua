function trycall(f,...)
	local r = { pcall(f,...) }
	if r[1] then
		table.remove(r,1)
		return unpack(r)
	else
		return nil, r[2]
	end
end

function printf(fmt,...)
	print(string.format(fmt,...))
end

function load_server_list(conf)
	local curr,prev = dofile(conf)
	local rv = {
		curr = curr;
		prev = prev;
	};
	local list = {}
	local raw  = {}
	local hash = {}
	for _,shard in pairs(curr) do
		for _,node in pairs(shard) do
			local hp = string.lower(node[3]) .. ':' .. tostring(node[4])
			if not hash[ hp ] then
				hash[hp] = true
				table.insert(raw, hp)
				table.insert(list,{ node[3],node[4] })
			end
		end
	end
	rv.list = list
	rv.raw = raw
	return rv
end
