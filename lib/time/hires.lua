local ffi = require("ffi")
local tonumber = _G.tonumber

module(...)

ffi.cdef[[
struct time_hires_timeval {
	uint64_t      tv_sec;
	uint64_t      tv_usec;
};
uint64_t time(uint64_t *t);
int gettimeofday(struct time_hires_timeval *tv, struct timezone *tz);
]]
local timeval = ffi.typeof("struct time_hires_timeval");

return function()
	local tv = timeval();
	ffi.C.gettimeofday(tv,nil);
	return tonumber(tv.tv_sec) + tonumber(tv.tv_usec)/1e6;
end
