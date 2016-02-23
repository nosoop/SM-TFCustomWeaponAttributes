/**
 * [TF2] Custom Weapon Attribute: Launches balls that stun opponents
 * 
 * Requires the "override projectile type" attribute set to 6 in your configuration.
 * I can't seem to set that up myself.
 * 
 * 
 */
#pragma semicolon 1
#include <sourcemod>

#include <tf2_stocks>
#include <tf2attributes>

#include <sdkhooks>
#include <sdktools>
#include <customweaponstf>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "[TF2] Custom Weapon Attribute: Fires Stunballs",
    author = "nosoop",
    description = "Launches balls that stun opponents.",
    version = PLUGIN_VERSION,
    url = "localhost"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_FIRES_STUNBALLS "fires stunballs"

#define DEGREES_PER_RADIAN 57.29577

ArrayList g_StunballEntities;

Handle g_hCTFPlayerGetMaxAmmo;

bool g_bWeaponDemonstration = false;

public void OnPluginStart() {
	g_StunballEntities = new ArrayList();
	
	PrepareGameData();
}

public void OnEntityDestroyed(int entity) {
	int index;
	if ((index = g_StunballEntities.FindValue(entity)) != -1) {
		g_StunballEntities.Erase(index);
	}
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false) && StrEqual(attrib, ATTR_FIRES_STUNBALLS)) {
		g_StunballEntities.Push(weapon);
		
		// this isn't working so fuck it, you'll just have to add "override projectile type" yourself
		// TF2Attrib_SetByDefIndex(weapon, 280, 6);
		// TF2Attrib_SetByDefIndex(weapon, "override projectile type", 6.0);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "tf_projectile_flare")) {
		// It's too early to get the spawn position when hooking spawn, so Think will have to do
		SDKHook(entity, SDKHook_Think, OnFlareSpawned);
	}
}

public void OnFlareSpawned(int flare) {
	// Gets the weapon associated with the flare.
	int hLauncher = GetEntPropEnt(flare, Prop_Send, "m_hLauncher");
	
	if (IsStunballWeapon(hLauncher)) {
		/**
		 * BUG:  Because we have to wait until the flare exists so we can get the proper angles,
		 * it may already be in a position where it can burn a player.
		 * 
		 * Basically, just don't be too close to a player.
		 * (We could possibly simulate the angles, but that sounds like a pain.)
		 */
		CreateStunballFromFlare(flare);
	}
}

int CreateStunballFromFlare(int flare) {
	int stunball = CreateEntityByName("tf_projectile_stun_ball");
	
	if (IsValidEntity(stunball)) {
		int hLauncher = GetEntPropEnt(flare, Prop_Send, "m_hLauncher");
		int hOwner = GetEntPropEnt(hLauncher, Prop_Data, "m_hOwner");
		
		bool bCritical = GetEntProp(flare, Prop_Send, "m_bCritical") > 0;
		
		SetEntPropEnt(stunball, Prop_Data, "m_hThrower", hOwner);
		SetEntProp(stunball, Prop_Data, "m_bIsLive", true);
		
		SetEntProp(stunball, Prop_Send, "m_bCritical", bCritical);
		
		float vecVelocity[3], vecOrigin[3];
		GetEntPropVector(flare, Prop_Data, "m_vecVelocity", vecVelocity);
		GetEntPropVector(flare, Prop_Data, "m_vecOrigin", vecOrigin);
		
		float vecPlayerEyePosition[3], vecEyeWeaponOffset[3];
		
		// Minigun firing offset
		// --- This is meant for the Weapon Demonstration video firing offset to look nice.
		GetClientEyePosition(hOwner, vecPlayerEyePosition);
		
		// Get a line vector from the eye's position to the stunball origin
		MakeVectorFromPoints(vecPlayerEyePosition, vecOrigin, vecEyeWeaponOffset);
		
		// Get the angle from the eye to the stunball origin
		float vecEyeWeaponAngle[3];
		GetVectorAngles(vecEyeWeaponOffset, vecEyeWeaponAngle);
		
		// Shift to the left by ~4 degrees
		vecEyeWeaponAngle[1] += 4.0;
		
		// Get and store the forward vector of the angle as the new offset
		float vecNewEyeWeaponOffset[3];
		GetAngleVectors(vecEyeWeaponAngle, vecNewEyeWeaponOffset, NULL_VECTOR, NULL_VECTOR);
		
		// Scale the unit vector to match the old length
		ScaleVector(vecNewEyeWeaponOffset, GetVectorLength(vecEyeWeaponOffset, false));
		
		// Add the relative offset back to the eye position and save
		AddVectors(vecPlayerEyePosition, vecNewEyeWeaponOffset, vecOrigin);
		// --- end weapon demonstration offset stuff
		
		// This is for the ball to spawn closer to what you'd expect (instead of at eye-level)
		static float flVerticalOffset = 35.0;
		vecOrigin[2] -= flVerticalOffset;
		
		AcceptEntityInput(flare, "Kill");
		
		/**
		 * Compensate for the vertical offset with this:
		 * v = sqrt( 0.5 * gravity * height )
		 * 
		 * Thanks, physics!
		 */
		vecVelocity[2] += SquareRoot(2 * 800 * flVerticalOffset);
		
		DispatchSpawn(stunball);
		TeleportEntity(stunball, vecOrigin, NULL_VECTOR, vecVelocity);
		
		SDKHook(stunball, SDKHook_Touch, OnStunballTouch);
	}
	return stunball;
}

public Action OnStunballTouch(int stunball, int other) {
	int hThrower = GetEntPropEnt(stunball, Prop_Data, "m_hThrower");
	
	if (other && other < MaxClients && IsPlayerAlive(other)) {
		
		if (GetEntProp(stunball, Prop_Data, "m_bIsLive")
				&& TF2_GetClientTeam(hThrower) != TF2_GetClientTeam(other)) {
			// Stun player
			OnStunballHit(stunball, other);
		} else if (other == hThrower) {
			int slot = TFWeaponSlot_Primary;
			int weapon = -1;
			while (IsValidEntity((weapon = GetPlayerWeaponSlot(hThrower, slot)))) {
				if (IsStunballWeapon(weapon)) {
					int nAmmo = GetAmmo(hThrower, weapon);
					
					if (nAmmo < GetWeaponMaxAmmo(hThrower, weapon)) {
						SetAmmo(hThrower, weapon, nAmmo + 1);
						AcceptEntityInput(stunball, "Kill");
						ClientCommand(hThrower, "playgamesound BaseCombatCharacter.AmmoPickup");
					}
					break;
				}
			}
		}
		
		SetVariantString("ParticleEffectStop");
		AcceptEntityInput(stunball, "DispatchEffect");
	}
	
	// TODO make sure that the object we are colliding with is not an invisible brush
	SetEntProp(stunball, Prop_Data, "m_bIsLive", false);
	
	// It touched a thing, so kill it after a second.
	if (!g_bWeaponDemonstration) {
		CreateTimer(1.0, Timer_DespawnBall, EntIndexToEntRef(stunball));
		AcceptEntityInput(stunball, "Kill");
	}
	
	return Plugin_Continue;
}

void OnStunballHit(int stunball, int victim) {
	int hThrower = GetEntPropEnt(stunball, Prop_Data, "m_hThrower");
	
	int damageFlags = DMG_CLUB;
	
	bool bCritical = GetEntProp(stunball, Prop_Send, "m_bCritical") > 0;
	
	if (bCritical) {
		damageFlags |= DMG_CRIT;
	}
	
	// Headshot detection
	// ...-ish.  It's not perfect, but it'll do.
	float vecStunballOrigin[3], vecVictimEyePosition[3];
	GetEntPropVector(stunball, Prop_Data, "m_vecOrigin", vecStunballOrigin);
	GetClientEyePosition(victim, vecVictimEyePosition);
	
	float flDistanceToFace = GetVectorDistance(vecStunballOrigin, vecVictimEyePosition);
	if (flDistanceToFace < 30.0) {
		TF2_StunPlayer(victim, 1.0, _, TF_STUNFLAGS_SMALLBONK, hThrower);
		SDKHooks_TakeDamage(victim, stunball, hThrower, 20.0, damageFlags, -1);
	} else {
		SDKHooks_TakeDamage(victim, stunball, hThrower, 15.0, damageFlags, -1);
	}
}

public Action Timer_DespawnBall(Handle timer, int entref) {
	int stunball = EntRefToEntIndex(entref);
	
	if (IsValidEntity(stunball)) {
		AcceptEntityInput(stunball, "Kill");
	}
}

bool IsStunballWeapon(int weapon) {
	return g_StunballEntities.FindValue(weapon) != -1;
}

stock void SetAmmo(int client, int iWeapon, int iAmmo) {
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if(iAmmoType != -1) SetEntProp(client, Prop_Data, "m_iAmmo", iAmmo, _, iAmmoType);
}

stock int GetAmmo(int client, int iWeapon) {
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	if (iAmmoType != -1) {
		return GetEntProp(client, Prop_Data, "m_iAmmo", _, iAmmoType);
	}
	return 0;
}

stock int GetMaxAmmo(int iClient, int iAmmoType, TFClassType iClass) { 
    if (iAmmoType == -1 || !iClass) {
        return -1;
    }

    if (g_hCTFPlayerGetMaxAmmo == INVALID_HANDLE) {
        LogError("SDKCall for GetMaxAmmo is invalid!");
        return -1;
    }
     
    return SDKCall(g_hCTFPlayerGetMaxAmmo, iClient, iAmmoType, iClass);
}

stock int GetWeaponMaxAmmo(int iClient, int iWeapon) {
    return GetMaxAmmo(iClient, GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType", 1),
			TF2_GetPlayerClass(iClient));
}


stock void PrepareGameData() {
    Handle hGameData = LoadGameConfigFile("tf2.cwa_fires_stunballs");
    if (hGameData == INVALID_HANDLE) {
        SetFailState("Unable to load required gamedata (tf2.cwa_fires_stunballs.txt)");
    }

    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTFPlayer::GetMaxAmmo");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
    PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);

    g_hCTFPlayerGetMaxAmmo = EndPrepSDKCall();
    
    delete hGameData;
}
