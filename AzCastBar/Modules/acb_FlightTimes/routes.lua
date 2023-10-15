if (not AzCastBarPluginFlight) then
	return
end

-- List of included flight times -- Was cleared as of patch 4.0.3a, as that patch changed so much, moved flight points, added a bunch of new ones
local flightTimeTable = {
};

-- Merge supplied data into user data
function AzCastBarPluginFlight:MergeSuppliedDatabase(destDB)
	if (not destDB) then
		destDB = {};
	end
	if (GetLocale() == "enUS") then
		for route, time in next, flightTimeTable do
			if (not destDB[route]) then
				destDB[route] = time;
			end
		end
	end
	flightTimeTable = nil;
	self.MergeSuppliedDatabase = nil;
	return destDB;
end