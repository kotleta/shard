--# create server master1 with script='lua2/master1.lua', lua_libs='lua2/lua/shard.lua'
--# create server master2 with script='lua2/master2.lua', lua_libs='lua2/lua/shard.lua'
--# start server master1
--# start server master2
--# set connection default
wait()

-- num keys
shard.shard(0)[1].uri

-- str keys
shard.shard('abc')[1].uri

--# stop server master1
--# stop server master2
--# cleanup server master1
--# cleanup server master2
--# stop server default
--# start server default
--# set connection default