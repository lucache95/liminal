# Godot MCP Setup Summary

## What Was Done

### 1. Moved Godot to /Applications
- Godot was in `~/Downloads/Godot.app` (v4.6.1 stable, universal macOS binary)
- Moved to `/Applications/Godot.app`
- Binary path: `/Applications/Godot.app/Contents/MacOS/Godot`

### 2. Installed LeeSinLiang/godot-mcp Server
- Cloned to `~/tools/godot-mcp` from https://github.com/LeeSinLiang/godot-mcp
- Ran `npm install` and `npm run build`
- Built output lives at `~/tools/godot-mcp/build/index.js`
- Had to fix npm cache permissions first: `sudo chown -R 501:20 ~/.npm`

### 3. Configured MCP for the Project
- Created `/Users/lucassenechal/Projects/caleb-game/godot-project/.mcp.json`:
```json
{
  "mcpServers": {
    "godot": {
      "command": "node",
      "args": ["/Users/lucassenechal/tools/godot-mcp/build/index.js"],
      "env": {
        "GODOT_PATH": "/Applications/Godot.app/Contents/MacOS/Godot"
      }
    }
  }
}
```

## Key Paths
- **Godot binary:** `/Applications/Godot.app/Contents/MacOS/Godot`
- **MCP server:** `~/tools/godot-mcp/build/index.js`
- **MCP config:** `/Users/lucassenechal/Projects/caleb-game/godot-project/.mcp.json`
- **Godot project:** `/Users/lucassenechal/Projects/caleb-game/godot-project/`

## Available MCP Tools
When Claude Code is run from the project directory, it has access to:
- **Project management:** `launch_editor`, `run_project`, `stop_project`, `list_projects`, `get_project_info`, `get_godot_version`
- **Scene editing:** `create_scene`, `add_node`, `load_sprite`, `save_scene`, `export_mesh_library`
- **Debugging:** `connect_remote_debugger`, `get_remote_debug_output`, `disconnect_remote_debugger`, `get_debug_output`, `capture_screenshot`
- **UID management (Godot 4.4+):** `get_uid`, `update_project_uids`

## How to Use
1. `cd /Users/lucassenechal/Projects/caleb-game/godot-project`
2. Start Claude Code — the MCP server auto-connects
3. Use `connect_remote_debugger` to get real-time debug output from the Godot editor
4. Claude can launch the editor, run the game, create/edit scenes, capture screenshots, and read errors
