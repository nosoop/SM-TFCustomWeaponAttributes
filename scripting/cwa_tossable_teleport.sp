/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <tf2_stocks>
#include <stocksoup/log_server>
#include <stocksoup/entity_tools>
#include <stocksoup/tf/entity_prefabs>
#include <stocksoup/tf/hud_notify>
#include <stocksoup/sdkutils>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute:  Tossable Teleporter",
    author = "nosoop",
    description = "Mad Milk replacement that teleports the thrower.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/SM-TFCustomWeaponAttributes/"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_TOSSABLE_TELEPORTER "is tossable teleporter"

ArrayList g_TossableTeleporters;

ConVar g_DemoPreventTeleport;

public void OnPluginStart() {
	g_TossableTeleporters = new ArrayList();
	
	g_DemoPreventTeleport = CreateConVar("cwa_demo_force_disable_teleporter", "0",
			"Disables the teleporter for demonstration purposes.", _, true, 0.0, true, 1.0);
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false)) {
		if (StrEqual(attrib, ATTR_TOSSABLE_TELEPORTER)) {
			g_TossableTeleporters.Push(weapon);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnEntityDestroyed(int entity) {
	int index;
	if ((index = g_TossableTeleporters.FindValue(entity)) != -1) {
		g_TossableTeleporters.Erase(index);
	}
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "tf_projectile_jar_milk")) {
		/**
		 * As it turns out, VPhysics updates occur a lot earlier than RequestFrame or Think
		 * hooks.  No more first-frame usage bug!
		 */
		SDKHook(entity, SDKHook_VPhysicsUpdate, TestMilkProjectile);
	}
}

void TestMilkProjectile(int entref) {
	int entity = EntRefToEntIndex(entref);
	if (entity && IsHookedMilkProjectile(entity)) {
		ReplaceMilkProjectile(entity);
	} else {
		SDKUnhook(entity, SDKHook_VPhysicsUpdate, TestMilkProjectile);
	}
}

/**
 * Checks if the thrower's secondary weapon has the tossable teleporter attribute.
 */
bool IsHookedMilkProjectile(int entity) {
	int hThrower = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	int hSecondaryWeapon = GetPlayerWeaponSlot(hThrower, TFWeaponSlot_Secondary);
	
	return g_TossableTeleporters.FindValue(hSecondaryWeapon) != -1;
}

void ReplaceMilkProjectile(int entity) {
	LogServer("threw a milk (%d)!", entity);
	
	int hThrower = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	TFTeam team = TF2_GetClientTeam(hThrower);
	
	float vecAngles[3], vecOrigin[3], vecVelocity[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", vecAngles);
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", vecOrigin);
	GetEntPropVector(entity, Prop_Send, "m_vInitialVelocity", vecVelocity);
	
	char modelName[PLATFORM_MAX_PATH];
	GetEntPropString(entity, Prop_Data, "m_ModelName", modelName, sizeof(modelName));
	
	AcceptEntityInput(entity, "Kill");
	
	int replacement = CreateEntityByName("prop_physics_override");
	if (IsValidEntity(replacement)) {
		SetEntityModel(replacement, modelName);
		
		// FSOLID_NOT_SOLID | FSOLID_TRIGGER from const.h
		SetEntProp(replacement, Prop_Data, "m_usSolidFlags", 0x0004 | 0x0008);
		SetEntProp(replacement, Prop_Data, "m_nSolidType", 6); // SOLID_VPHYSICS
		SetEntProp(replacement, Prop_Send, "m_CollisionGroup", 1); // COLLISION_GROUP_DEBRIS
		
		// TeleportEntity(replacement, vecOrigin, vecAngles, vecVelocity);
		DispatchSpawn(replacement);
		
		TeleportEntity(replacement, vecOrigin, vecAngles, vecVelocity);
		
		int glow = TF2_AttachGlowModel(replacement);
		if (IsValidEntity(glow)) {
			SetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity", hThrower);
			SDKHook(glow, SDKHook_SetTransmit, OnBuildingGlow);
		}
		
		int trail = CreateParticle(team == TFTeam_Red ?
				"pipebombtrail_red" : "pipebombtrail_blue");
		if (IsValidEntity(trail)) {
			TeleportEntity(trail, vecOrigin, NULL_VECTOR, NULL_VECTOR);
			ParentEntity(replacement, trail);
		}
		
		LogServer("Model: %s", modelName);
		LogServer("Origin: %.3f %.3f %.3f", vecOrigin[0], vecOrigin[1], vecOrigin[2]);
		LogServer("Angles: %.3f %.3f %.3f", vecAngles[0], vecAngles[1], vecAngles[2]);
		LogServer("Velocity: %.3f %.3f %.3f", vecVelocity[0], vecVelocity[1], vecVelocity[2]);
		
		DataPack dataPack;
		CreateDataTimer(5.0, OnTossableActivate, dataPack, TIMER_FLAG_NO_MAPCHANGE);
		
		dataPack.WriteCell(GetClientUserId(hThrower));
		dataPack.WriteCell(EntIndexToEntRef(replacement));
	}
}

public Action OnTossableActivate(Handle timer, DataPack dataPack) {
	dataPack.Reset();
	int hThrower = GetClientOfUserId(dataPack.ReadCell());
	int projectile = EntRefToEntIndex(dataPack.ReadCell());
	
	if (IsValidEntity(projectile)) {
		if (hThrower && IsPlayerAlive(hThrower)) {
			OnTossableTeleportUse(hThrower, projectile);
		}
		AcceptEntityInput(projectile, "Kill");
	}
	
	return Plugin_Handled;
}

void OnTossableTeleportUse(int hThrower, int projectile) {
	TFTeam team = TF2_GetClientTeam(hThrower);
	float vecDestination[3], vecSource[3];
	GetEntPropVector(projectile, Prop_Data, "m_vecAbsOrigin", vecDestination);
	GetClientAbsOrigin(hThrower, vecSource);
	
	TF2_AddCondition(hThrower, TFCond_TeleportedGlow, 6.0);
	
	int entranceParticle = CreateParticle
			(team == TFTeam_Red ? "teleported_red" : "teleported_blue");
	
	bool bValidDestination = FindValidTeleportDestination(hThrower, vecDestination,
			vecDestination);
	
	if (bValidDestination && !g_DemoPreventTeleport.BoolValue) {
		if (IsValidEntity(entranceParticle)) {
			TeleportEntity(entranceParticle, vecSource, NULL_VECTOR, NULL_VECTOR);
		}
		
		// Simulated teleporter effect.
		// https://github.com/danielmm8888/TF2Classic/blob/7fa53f644451cce72e1627cf5d8c6291401c7a65/src/game/server/tf/tf_obj_teleporter.cpp#L799
		UTIL_ScreenFade(hThrower, { 255, 255, 255, 100 }, 0.25, 0.4);
		
		EmitGameSoundToAll("Building_Teleporter.Send", hThrower);
		
		int exitParticle = CreateParticle
				(team == TFTeam_Red ? "teleportedin_red" : "teleportedin_blue");
		
		if (IsValidEntity(exitParticle)) {
			TeleportEntity(exitParticle, vecDestination, NULL_VECTOR, NULL_VECTOR);
		}
		
		TeleportEntity(hThrower, vecDestination, NULL_VECTOR, NULL_VECTOR);
	} else {
		TF_HudNotifyCustom(hThrower, "obj_status_tele_exit", team,
				"Not enough space for a safe teleport.");
		EmitGameSoundToClient(hThrower, "Player.DenyWeaponSelection");
	}
}

/** 
 * Attempts to find a nearby position that a player can be teleported to without getting stuck.
 * The position is stored in vecDestination.
 * 
 * @return true if a space is found
 */
bool FindValidTeleportDestination(int client, const float vecPosition[3],
		float vecDestination[3]) {
	float vecMins[3], vecMaxs[3];
	GetClientMins(client, vecMins);
	GetClientMaxs(client, vecMaxs);
	
	Handle trace = TR_TraceHullFilterEx(vecPosition, vecPosition, vecMins, vecMaxs,
			MASK_PLAYERSOLID, TeleportTraceFilter, client);
	
	bool valid = !TR_DidHit(trace);
	delete trace;
	
	if (valid) {
		vecDestination = vecPosition;
		
		LogServer("Center is fine.");
		return true;
	}
	
	// Basic unstuck handling.
	/** 
	 * Basically we treat the corners and center edges of the player's bounding box as potential
	 * teleport destination candidates.
	 */
	float vecTestPosition[3];
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			float vecOffset[] = { 0.0, 0.0, 10.0 };
			
			switch (x) {
				case -1: { vecOffset[0] = vecMins[0]; }
				case 1: { vecOffset[0] = vecMaxs[0]; }
			}
			
			switch (y) {
				case -1: { vecOffset[1] = vecMins[1]; }
				case 1: { vecOffset[1] = vecMaxs[1]; }
			}
			
			AddVectors(vecPosition, vecOffset, vecTestPosition);
			
			trace = TR_TraceHullFilterEx(vecTestPosition, vecTestPosition, vecMins, vecMaxs,
					MASK_PLAYERSOLID, TeleportTraceFilter, client);
			
			valid = !TR_DidHit(trace);
			
			delete trace;
			
			if (valid) {
				vecDestination = vecTestPosition;
				return true;
			}
		}
	}
	
	return false;
}

/** 
 * Return true if teleport should be stopped.
 */
public bool TeleportTraceFilter(int entity, int contents, int client) {
	return entity > 1 && client != entity;
}

public Action OnBuildingGlow(int glow, int client) {
	int hOwner = GetEntPropEnt(glow, Prop_Send, "m_hOwnerEntity");
	
	if (hOwner == client) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

stock void DataPack_ReadVector(DataPack dataPack, float vec[3]) {
	vec[0] = dataPack.ReadFloat();
	vec[1] = dataPack.ReadFloat();
	vec[2] = dataPack.ReadFloat();
}

stock void DataPack_WriteVector(DataPack dataPack, const float vec[3]) {
	for (int i = 0; i < 3; i++) {
		dataPack.WriteFloat(vec[i]);
	}
}

int CreateParticle(const char[] effectName) {
	int particle = CreateEntityByName("info_particle_system");
	
	if (IsValidEdict(particle)) {
		DispatchKeyValue(particle, "effect_name", effectName);
		DispatchSpawn(particle);
		
		ActivateEntity(particle);
		AcceptEntityInput(particle, "start");
	}
	return particle;
}

