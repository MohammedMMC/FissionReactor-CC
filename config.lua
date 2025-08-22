return {
	-- UI refresh interval (seconds)
	REFRESH_INTERVAL = 0.05,

	-- Safety thresholds (critical shutdown)
	SAFETY_TEMP_F = 5000,   -- °F
	SAFETY_DMG_HIGH = 50,   -- %

	-- Safety thresholds (soft shutdown)
	SAFETY_COOLANT_MIN = 20, -- %
	SAFETY_FUEL_MIN = 5,     -- %
	SAFETY_HEATED_MAX = 99,  -- %
	SAFETY_WASTE_MAX = 99,   -- %
	SAFETY_DMG_WARN = 20,    -- %

	-- Auto-restart thresholds after non-high danger shutdown
	SAFETY_RESTART_COOLANT_MIN = 15, -- %
	SAFETY_RESTART_FUEL_MIN = 5,     -- %
	SAFETY_RESTART_HEATED_MAX = 99,  -- %
	SAFETY_RESTART_WASTE_MAX = 99,   -- %
	SAFETY_RESTART_DMG_MAX = 20,     -- %
	-- If omitted, reactor uses SAFETY_TEMP_F
	-- SAFETY_RESTART_TEMP_MAX = 5000,
}
