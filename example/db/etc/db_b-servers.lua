return {
	{ -- shard 1
		{ 'rw',1,'127.102.1.0',33013 },
		{ 'ro',1,'127.102.1.1',33013 },
	},
	{ -- shard 2
		{ 'rw',1,'127.102.2.0',33013 },
		{ 'ro',1,'127.102.2.1',33013 },
	},
	{ -- shard 3
		{ 'rw',1,'127.102.3.0',33013 },
		{ 'ro',1,'127.102.3.1',33013 },
	},
}