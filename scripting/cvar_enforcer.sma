/*

Credits
Exolent - 99% of the code
edon1337 - player freeze
Jimmie - plugin release

*/

#include <amxmodx>
#include <hamsandwich>
#include <fvault>
#include <fakemeta>

#define PLUGIN "Cvar Enforcer"
#define VERSION "0.1"
#define AUTHOR "Exolent"

new const g_agree_vault[] = "cvar_enforcer_agree";
new bool:g_agreed[33];

new const g_client_cvar_names[][] =
{
	"developer",
	"fps_override",
	"fps_max",
	"cl_forwardspeed",
	"cl_sidespeed",
	"cl_backspeed"
};

new const g_client_cvar_values[sizeof(g_client_cvar_names)][] =
{
	"0",
	"0",
	"99.5",
	"400",
	"400",
	"400"
};

new Trie:g_client_cvar_index;

enum
{
	STRINGTYPE_ERROR,
	STRINGTYPE_INTEGER,
	STRINGTYPE_FLOAT
};

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR);

	g_client_cvar_index = TrieCreate();

	for( new i = 0; i < sizeof(g_client_cvar_names); i++ )
	{
		TrieSetCell(g_client_cvar_index, g_client_cvar_names[i], i);
	}

	RegisterHam(Ham_Spawn, "player", "FwdPlayerSpawn", 1);
}

public plugin_end()
{
	TrieDestroy(g_client_cvar_index);
}

public client_authorized(client)
{
	if( !is_user_bot(client) )
	{
		static authid[35];
		get_user_authid(client, authid, sizeof(authid) - 1);
		
		if( fvault_get_keynum(g_agree_vault, authid) == -1 )
		{
			g_agreed[client] = false;
		}
		else
		{
			g_agreed[client] = true;
			
			for( new i = 0; i < sizeof(g_client_cvar_names); i++ )
			{
				client_cmd(client, "%s %s", g_client_cvar_names[i], g_client_cvar_values[i]);
			}
			
			set_task(1.0, "TaskCheckCvars", client);
		}
	}
}

public client_putinserver(client)
{
	if( is_user_bot(client) ) //client is bot, so don't show agree menu.
	{
		g_agreed[client] = true;
	}
}

public client_disconnect(client)
{
	remove_task(client);
}

public FwdPlayerSpawn(client)
{
	if( is_user_alive(client) )
	{
		if( !g_agreed[client] )
		{
			SetUserFrozen( client, true );
			ShowAgreeMenu( client );
		}
	}
}

SetUserFrozen( client, bool:bFrozen ) {
    if( bFrozen ) 
	{
    	set_pev( client, pev_flags, pev( client, pev_flags ) | FL_FROZEN );
	}
	else 
	{
		set_pev( client, pev_flags, pev( client, pev_flags ) & ~ FL_FROZEN );
	}
}

ShowAgreeMenu( client )
{
	static szTitle[ 256 ];
	if( !szTitle[ 0 ] )
	{
		new iLen = copy( szTitle, 255, "This server requires:^n" );
		
		for( new i = 0; i < sizeof( g_client_cvar_names ); i++ )
		{
			iLen += formatex( szTitle[ iLen ], 255 - iLen, "\d- \r%s %s^n", g_client_cvar_names[ i ], g_client_cvar_values[ i ] );
		}
		
		add( szTitle, 255, "^n\yDo you accept this?" );
	}
	
	new hMenu = menu_create( szTitle, "MenuAgree" );
	menu_additem( hMenu, "Yes", "1" );
	menu_additem( hMenu, "No \r[ \wYou will be kicked! \r]", "2" );
	menu_additem( hMenu, "Yes and don't ask again", "3" );
	menu_setprop( hMenu, MPROP_EXIT, MEXIT_NEVER );
	
	menu_display( client, hMenu );
}

public MenuAgree(client, menu, item)
{
	if( item == MENU_EXIT ) return;
	
	static _access, info[3], callback;
	menu_item_getinfo(menu, item, _access, info, sizeof(info) - 1, _, _, callback);
	
	if( info[0] != '2' )
	{
		g_agreed[client] = true;
		
		for( new i = 0; i < sizeof(g_client_cvar_names); i++ )
		{
			client_cmd(client, "%s %s", g_client_cvar_names[i], g_client_cvar_values[i]);
		}
		
		set_task(1.0, "TaskCheckCvars", client);

		SetUserFrozen( client, false );
		
		static authid[35];
		get_user_authid(client, authid, sizeof(authid) - 1);
		
		if( info[0] == '3' )
		{
			fvault_set_data(g_agree_vault, authid, "1");
		}
	}
	else
	{
		static const szReason[ ] = "You must agree to use legal jump settings to play here!";
		
		emessage_begin( MSG_ONE, SVC_DISCONNECT, _, client );
		ewrite_string( szReason );
		emessage_end( );
	}
}

public TaskCheckCvars(client)
{
	query_client_cvar(client, g_client_cvar_names[0], "QueryCvar");
}

public QueryCvar(client, const cvar_name[], const cvar_value[])
{
	new type = GetStringNumType(cvar_value);
	
	static cvar;
	TrieGetCell(g_client_cvar_index, cvar_name, cvar);
	
	if( type == STRINGTYPE_ERROR	
	|| type == STRINGTYPE_INTEGER && str_to_num(cvar_value) != str_to_num(g_client_cvar_values[cvar])
	|| type == STRINGTYPE_FLOAT && str_to_float(cvar_value) != str_to_float(g_client_cvar_values[cvar]) )
	{
		static authid[35];
		get_user_authid(client, authid, sizeof(authid) - 1);
		
		if( fvault_get_keynum(g_agree_vault, authid) >= 0 )
		{
			fvault_remove_key(g_agree_vault, authid);
		}
		
		static reason[192];
		formatex(reason, sizeof(reason) - 1, "You must use legal jump settings!^nYour '%s' must be %s!", cvar_name, g_client_cvar_values[cvar]);
		
		emessage_begin(MSG_ONE, SVC_DISCONNECT, _, client);
		ewrite_string(reason);
		emessage_end();
		
		return;
	}
	
	query_client_cvar(client, g_client_cvar_names[(cvar + 1) % sizeof(g_client_cvar_names)], "QueryCvar");
}

GetStringNumType(const string[])
{
	new len = strlen(string);
	if( len )
	{
		new bool:period = false;
		for( new i = 0; i < len; i++ )
		{
			if( '0' <= string[i] <= '9' ) continue;
			
			if( string[i] == '.' && !period )
			{
				period = true;
				continue;
			}
			
			return STRINGTYPE_ERROR;
		}
		
		return period ? STRINGTYPE_FLOAT : STRINGTYPE_INTEGER;
	}
	
	return STRINGTYPE_ERROR;
}

