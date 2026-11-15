# Bug Fixes
* Fix a Lua error on every stun, fear, root or other loss of control effect ("attempted to index a table that cannot be indexed with secret keys"): WoW Forever now hides the kind of effect from addons, so GearMenu holds a queued item swap back until any loss of control effect ends - a root or silence now also delays the swap until it wears off
