/**
 * Sourcemod 1.7 Plugin Template
 */
#pragma semicolon 1
#include <sourcemod>

#include <sdkhooks>
#include <sdktools>

#pragma newdecls required

#define PLUGIN_VERSION "0.0.0"
public Plugin myinfo = {
    name = "Plugin name!",
    author = "Author!",
    description = "Description!",
    version = PLUGIN_VERSION,
    url = "localhost"
}

#define CW2_PLUGIN_NAME "custom-weapon-soup"
#define ATTR_PROJECTILE_LENGTHDIR "projectile lengthdirheight"
#define ATTR_PROJECTILE_SPEED "projectile speed factor"

ArrayList g_LengthdirWeapons;
ArrayList g_ProjectileSpeedWeapons;

enum AttributeValues {
	Attribute_Length = 0,
	Attribute_Direction,
	Attribute_Height
};

public void OnPluginStart() {
	g_LengthdirWeapons = new ArrayList(4);
	g_ProjectileSpeedWeapons = new ArrayList(2);
}

public Action CustomWeaponsTF_OnAddAttribute(int weapon, int client, const char[] attrib,
		const char[] plugin, const char[] value) {
	// Attach attribute if desired
	if (StrEqual(plugin, CW2_PLUGIN_NAME, false)) {
		if (StrEqual(attrib, ATTR_PROJECTILE_LENGTHDIR)) {
			int index;
			
			if ( (index = g_LengthdirWeapons.FindValue(weapon)) == -1)  {
				index = g_LengthdirWeapons.Push(weapon);
			}
			
			float values[3];
			StringToVector(value, values);
			for (int i = 0; i < 3; i++) {
				g_LengthdirWeapons.Set(index, values[i], i + 1);
			}
			PrintToServer("Hooked weapon %d", weapon);
			return Plugin_Handled;
		}
		
		if (StrEqual(attrib, ATTR_PROJECTILE_SPEED)) {
			int index;
			
			if ( (index = g_ProjectileSpeedWeapons.FindValue(weapon)) == -1) {
				index = g_ProjectileSpeedWeapons.Push(weapon);
			}
			
			float flSpeedFactor;
			flSpeedFactor = StringToFloat(value);
			
			g_ProjectileSpeedWeapons.Set(index, flSpeedFactor, 1);
			PrintToServer("Hooked weapon %d", weapon);
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrContains(classname, "tf_projectile_") == 0) {
		// It's too early to get the spawn position when hooking spawn, so Think will have to do
		SDKHook(entity, SDKHook_Think, OnProjectileSpawned);
		PrintToServer("Hooking %s", classname);
	}
}

public void OnProjectileSpawned(int projectile) {
	int hLauncher = GetEntPropEnt(projectile, Prop_Send, "m_hLauncher");
	
	float values[3];
	if (GetAttributeValue(hLauncher, values)) {
		int hOwner = GetEntPropEnt(hLauncher, Prop_Data, "m_hOwner");
		
		float vecVelocity[3], vecOrigin[3];
		GetEntPropVector(projectile, Prop_Data, "m_vecVelocity", vecVelocity);
		GetEntPropVector(projectile, Prop_Data, "m_vecOrigin", vecOrigin);
		
		float vecVelocityOld[3], vecOriginOld[3];
		GetEntPropVector(projectile, Prop_Data, "m_vecVelocity", vecVelocityOld);
		GetEntPropVector(projectile, Prop_Data, "m_vecOrigin", vecOriginOld);
		
		float vecPlayerEyePosition[3], vecEyeWeaponOffset[3];
		
		// Firing offset
		// Blatantly modified from the last plugin.
		
		// --- This is meant for the Weapon Demonstration video firing offset to look nice.
		GetClientEyePosition(hOwner, vecPlayerEyePosition);
		
		// Get a line vector from the eye's position to the stunball origin
		MakeVectorFromPoints(vecPlayerEyePosition, vecOrigin, vecEyeWeaponOffset);
		
		// Get the angle from the eye to the stunball origin
		float vecEyeWeaponAngle[3];
		GetVectorAngles(vecEyeWeaponOffset, vecEyeWeaponAngle);
		
		// Shift to the left by ~4 degrees
		vecEyeWeaponAngle[1] += values[Attribute_Direction];
		
		// Get and store the forward vector of the angle as the new offset
		float vecNewEyeWeaponOffset[3];
		GetAngleVectors(vecEyeWeaponAngle, vecNewEyeWeaponOffset, NULL_VECTOR, NULL_VECTOR);
		
		// Scale the unit vector relative to attribute
		ScaleVector(vecNewEyeWeaponOffset,
				GetVectorLength(vecEyeWeaponOffset, false) * 1.0);
		
		// Add the relative offset back to the eye position and save
		AddVectors(vecPlayerEyePosition, vecNewEyeWeaponOffset, vecOrigin);
		// --- end weapon demonstration offset stuff
		
		// This is for the ball to spawn closer to what you'd expect (instead of at eye-level)
		vecOrigin[2] -= values[Attribute_Height];
		
		/**
		 * Compensate for the vertical offset aiming with this:
		 * v = sqrt( 0.5 * gravity * height )
		 * 
		 * Thanks, physics!
		 */
		// TODO check if affected by gravity
		// vecVelocity[2] += SquareRoot(2 * 800 * flVerticalOffset);
		
		PrintToServer("Changed projectile %d settings", projectile);
		TeleportEntity(projectile, vecOrigin, NULL_VECTOR, vecVelocity);
		PrintToServer("Old: origin { %f, %f, %f }, velocity { %f, %f, %f }",
				vecOriginOld[0], vecOriginOld[1], vecOriginOld[2], 
				vecVelocityOld[0], vecVelocityOld[1], vecVelocityOld[2]);
		PrintToServer("New: origin { %f, %f, %f }, velocity { %f, %f, %f }",
				vecOrigin[0], vecOrigin[1], vecOrigin[2], 
				vecVelocity[0], vecVelocity[1], vecVelocity[2]);
		PrintToServer("Attribute values { %f, %f, %f }",
				values[Attribute_Length], values[Attribute_Direction], values[Attribute_Height]);
		
	}
	
	int index;
	if ( (index = g_ProjectileSpeedWeapons.FindValue(hLauncher)) != -1 ) {
		float vecVelocity[3], flOldSpeed;
		float flSpeedFactor = g_ProjectileSpeedWeapons.Get(index, 1);
		
		
		GetEntPropVector(projectile, Prop_Data, "m_vecVelocity", vecVelocity);
		flOldSpeed = GetVectorLength(vecVelocity);
		
		ScaleVector(vecVelocity, flSpeedFactor);
		
		TeleportEntity(projectile, NULL_VECTOR, NULL_VECTOR, vecVelocity);
		PrintToServer("Modified projectile %d by weapon %d", projectile, hLauncher);
		PrintToServer("Velocity: old %f, new %f (scale %f)", flOldSpeed,
				GetVectorLength(vecVelocity), flSpeedFactor);w
	} else {
		PrintToServer("Did not modify projectile %d by weapon %d", projectile, hLauncher);
	}
	
	SDKUnhook(projectile, SDKHook_Think, OnProjectileSpawned);
}

bool GetAttributeValue(int weapon, float value[3]) {
	int index;
	if ( (index = g_LengthdirWeapons.FindValue(weapon)) != -1) {
		for (int i = 0; i < 3; i++) {
			value[i] = g_LengthdirWeapons.Get(index, i + 1);
		}
		return true;
	}
	return false;
}

bool StringToVector(const char[] str, float vec[3]) {
	char substr[3][16];
	int count = ExplodeString(str, " ", substr, sizeof(substr), sizeof(substr[]));
	
	for (int i = 0; i < count; i++) {
		vec[i] = StringToFloat(substr[i]);
	}
	return count > 0;
}