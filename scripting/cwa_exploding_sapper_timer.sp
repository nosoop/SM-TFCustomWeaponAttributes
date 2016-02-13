/**
 * Custom Weapons Attribute: Exploding Sapper
 * Requested by Karma Charger
 * 5k */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <customweaponstf>
#include <tf2_stocks>
#include <tf2_morestocks>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Exploding Sapper",
    author = "nosoop",
    description = "Sapper goes boom.",
    version = PLUGIN_VERSION,
    url = "https://github.com/nosoop/"
}

#define PARTICLE_NAME_LENGTH 32

#define CW2_PLUGIN_NAME "custom-weapon-soup-exploding-sapper"
#define ATTR_EXPLODING_SAPPER "exploding sapper"
#define ATTR_EXPLODING_SAPPER_RADIUS "exploding sapper radius"
#define ATTR_EXPLODING_SAPPER_DAMAGE "exploding sapper damage"
#define ATTR_EXPLODING_SAPPER_EFFECT "exploding sapper particle"
#define ATTR_EXPLODING_SAPPER_SOUND "exploding sapper sound"
#define ATTR_EXPLODING_SAPPER_TIME "exploding sapper time"
#define ATTR_EXPLODING_SAPPER_DISABLE_TIME "exploding sapper disable time"

// I can't be bothered to pick an appropriate particle effect
#define SAPPER_DEFAULT_EXPLODING_EFFECT "ghost_appearation"

ArrayList g_ExplodingSapperEntities;

float g_flClientSapLockTime[MAXPLAYERS+1];

bool g_bSpewGarbage = false;

public void OnPluginStart() {
	g_ExplodingSapperEntities = new ArrayList();
	
	HookEvent("player_sapped_object", OnObjectSapped);
	HookEvent("post_inventory_application", OnPlayerLoadoutRefresh);
	
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false)) {
		// NOTE: do not use sm_custom_addattribute -- it does not expose keyvalues
		if (StrEqual(attrib, ATTR_EXPLODING_SAPPER) && StringToInt(value) > 0) {
			g_ExplodingSapperEntities.Push(weapon);
		}
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnClientPutInServer(int client) {
	g_flClientSapLockTime[client] = 0.0;
	
	// TODO fully prevent client from switching weapon
	SDKHook(client, SDKHook_WeaponCanSwitchTo, OnSapperSwitch);
}

public void OnPlayerLoadoutRefresh(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	g_flClientSapLockTime[client] = 0.0;
}

public void OnObjectSapped(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	int buildingtype = event.GetInt("object");
	int sapperid = event.GetInt("sapperid");
	
	char classname[64];
	GetEntityClassname(sapperid, classname, sizeof(classname));
	
	int building = GetEntPropEnt(sapperid, Prop_Data, "m_hParent");
	
	DebugToServer("building %d (type %d) being sapped by sapper %d (%s) from player %N",
			building, buildingtype, sapperid, classname, attacker);
	
	// the sapperid is not the weapon's id; we'll just check the owner's 
	int sapper = GetPlayerWeaponSlot(attacker, view_as<int>(TF2ItemSlot_Sapper));
	if (IsExplodingSapper(sapper)) {
		KeyValues customweapon = view_as<KeyValues>(
				CusWepsTF_GetClientWeapon(attacker, view_as<int>(TF2ItemSlot_Sapper)));
		DebugToServer("custom weapon handle %d", customweapon);
		
		float flSapperDamage = 216.0;
		float flSapperRadius = 300.0;
		char sapperExplodeParticle[PARTICLE_NAME_LENGTH] = "ghost_appearation";
		char sapperExplodeSound[PLATFORM_MAX_PATH] = "";
		float flSapperTime = 5.0;
		
		float flSapperDisableTime = 2.0;
		
		if (customweapon != null) {
			customweapon.Rewind();
			if (customweapon.JumpToKey("attributes", false)) {
				flSapperDamage =
						customweapon.GetFloat(ATTR_EXPLODING_SAPPER_DAMAGE ...  "/value",
						flSapperDamage);
				flSapperRadius =
						customweapon.GetFloat(ATTR_EXPLODING_SAPPER_RADIUS ... "/value",
						flSapperRadius);
				customweapon.GetString(ATTR_EXPLODING_SAPPER_EFFECT ... "/value",
						sapperExplodeParticle, sizeof(sapperExplodeParticle),
						sapperExplodeParticle);
				flSapperTime =
						customweapon.GetFloat(ATTR_EXPLODING_SAPPER_TIME ... "/value",
						flSapperTime);
				customweapon.GetString(ATTR_EXPLODING_SAPPER_SOUND ... "/value",
						sapperExplodeSound, sizeof(sapperExplodeSound), sapperExplodeSound);
				flSapperDisableTime =
						customweapon.GetFloat(ATTR_EXPLODING_SAPPER_DISABLE_TIME ... "/value",
						flSapperDisableTime);
			}
		}
		
		DebugToServer("Sapper info: damage %f, radius %f, particle %s, time %f",
				flSapperDamage, flSapperRadius, sapperExplodeParticle, flSapperTime);
		DebugToServer("... sound %s", sapperExplodeSound);
		
		DataPack sapperData;
		CreateDataTimer(flSapperTime, Timer_ExplodingSapper, sapperData);
		sapperData.WriteCell(attacker);
		sapperData.WriteCell(sapperid);
		sapperData.WriteCell(building);
		sapperData.WriteFloat(flSapperDamage);
		sapperData.WriteFloat(flSapperRadius);
		sapperData.WriteString(sapperExplodeParticle);
		sapperData.WriteString(sapperExplodeSound);
		
		ForceSwitchFromSecondaryWeapon(attacker);
		SetSapperTimer(attacker, flSapperDisableTime);
	}
}

public Action Timer_ExplodingSapper(Handle timer, DataPack sapperData) {
	sapperData.Reset();
	
	char sapperExplodeParticle[PARTICLE_NAME_LENGTH];
	char sapperExplodeSound[PLATFORM_MAX_PATH];
	
	int attacker = sapperData.ReadCell();
	int sapperid = sapperData.ReadCell();
	int building = sapperData.ReadCell();
	float flSapperDamage = sapperData.ReadFloat();
	float flSapperRadius = sapperData.ReadFloat();
	sapperData.ReadString(sapperExplodeParticle, sizeof(sapperExplodeParticle));
	sapperData.ReadString(sapperExplodeSound, sizeof(sapperExplodeSound));
	
	if (IsValidEntity(sapperid)) {
		DebugToServer("Sapper validating");
		int validateBuilding = GetEntPropEnt(sapperid, Prop_Data, "m_hParent");
		if (building != validateBuilding) {
			DebugToServer("Sapper failed to validate");
			return Plugin_Handled;
		}
		DebugToServer("Sapper info: damage %f, radius %f, particle %s",
				flSapperDamage, flSapperRadius, sapperExplodeParticle);
		float vecOrigin[3];
		GetEntPropVector(validateBuilding, Prop_Data, "m_vecOrigin", vecOrigin);
		
		int bomb = TF2_CreateGenericBomb(vecOrigin, flSapperDamage, flSapperRadius,
				sapperExplodeParticle, sapperExplodeSound);
		SDKHooks_TakeDamage(bomb, attacker, attacker, 5.0);
		AcceptEntityInput(bomb, "Detonate");
		AcceptEntityInput(bomb, "Kill");
		
		DebugToServer("Sapper exploded?");
		
		if (IsValidEntity(sapperid)) {
			AcceptEntityInput(sapperid, "Kill");
		}
	}
	return Plugin_Handled;
}

stock int TF2_CreateGenericBomb(float vecOrigin[3], float flDamage = 0.0, float flRadius = 0.0,
		const char[] strParticle = "", const char[] strSound = "") {
	int iBomb = CreateEntityByName("tf_generic_bomb");
	DispatchKeyValueVector(iBomb, "origin", vecOrigin);
	DispatchKeyValueFloat(iBomb, "damage", flDamage);
	DispatchKeyValueFloat(iBomb, "radius", flRadius);
	DispatchKeyValue(iBomb, "health", "1");
	
	if (strlen(strParticle) > 0) {
		DispatchKeyValue(iBomb, "explode_particle", strParticle);
	}
	
	if (strlen(strSound) > 0) {
		DispatchKeyValue(iBomb, "sound", strSound);
	}
	
	char netclass[32];
	GetEntityNetClass(iBomb, netclass, sizeof(netclass));
	DebugToServer("bomb entity %s", netclass);
	
	DispatchSpawn(iBomb);
	return iBomb;
}  

public void OnEntityDestroyed(int entity) {
	int pos;
	if ((pos = g_ExplodingSapperEntities.FindValue(entity)) > -1) {
		g_ExplodingSapperEntities.Erase(pos);
	}
}

void ForceSwitchFromSecondaryWeapon(int client) {
	if (IsValidEntity(GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Melee)))) {
		ClientCommand(client, "slot3");
	} else if (IsValidEntity(GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Primary)))) {
		ClientCommand(client, "slot1");
	} else {
		// we can't really control it
	}
}

public Action OnSapperSwitch(int client, int weapon) {
	if (weapon == GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper))
			&& g_flClientSapLockTime[client] > GetGameTime()) {
		EmitGameSoundToClient(client, "Player.DenyWeaponSelection");
		
		TF_HudNotifyCustom(client, "obj_status_sapper", TF2_GetClientTeam(client),
				"Sapper is disabled for another %d seconds.",
				RoundToCeil(g_flClientSapLockTime[client] - GetGameTime()));
		
		// Alternatively we can just allow the weapon switch but also prevent attack 
		SetEntPropFloat(weapon, Prop_Data, "m_flNextPrimaryAttack", g_flClientSapLockTime[client]);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void SetSapperTimer(int client, float cooldown) {
	float regenTime = GetGameTime() + cooldown;
	
	int sapper = GetPlayerWeaponSlot(client, view_as<int>(TF2ItemSlot_Sapper));
	SetEntPropFloat(sapper, Prop_Send, "m_flEffectBarRegenTime", regenTime);
	g_flClientSapLockTime[client] = regenTime;
	
	DataPack pack;
	CreateDataTimer(cooldown, Timer_OnSapperTimerDone, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteFloat(regenTime);
}

public Action Timer_OnSapperTimerDone(Handle timer, DataPack pack) {
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	float regenTime = pack.ReadFloat();
	
	if (g_flClientSapLockTime[client] == regenTime && IsPlayerAlive(client)) {
		EmitGameSoundToClient(client, "TFPlayer.ReCharged");
	}
	return Plugin_Handled;
}

stock void TF_HudNotifyCustom(int client, const char[] icon, TFTeam team, const char[] format,
		any ...) {
	if (client <= 0 || client > MaxClients) {
		ThrowError("Invalid client index %d", client);
	} else if (!IsClientInGame(client)) {
		ThrowError("Client %d is not in game", client);
	}
	
	char buffer[256];
	VFormat(buffer, sizeof(buffer), format, 5);
	
	TF_HudNotifyCustomParams(view_as<BfWrite>(StartMessageOne("HudNotifyCustom", client)),
			buffer, icon, team);
}

stock void TF_HudNotifyCustomParams(BfWrite bitbuf, const char[] message, const char[] icon,
		TFTeam team) {
	bitbuf.WriteString(message);
	bitbuf.WriteString(icon);
	bitbuf.WriteByte(view_as<int>(team));
	
	EndMessage();
}

bool IsExplodingSapper(int weapon) {
	return g_ExplodingSapperEntities.FindValue(weapon) > -1;
}

void DebugToServer(const char[] fmt, any ...) {
	if (g_bSpewGarbage) {
		char buffer[256];
		VFormat(buffer, sizeof(buffer), fmt, 2);
		PrintToServer("%s", buffer);
	}
}