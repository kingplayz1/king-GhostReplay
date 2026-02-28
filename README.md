# GhostReplay: Elite Racing Framework for FiveM

![Version](https://img.shields.io/badge/version-2.2.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![FiveM](https://img.shields.io/badge/FiveM-Supported-orange.svg)

**GhostReplay Elite** is a professional-grade, high-performance racing and replay system for FiveM. It transforms the standard GTA V racing experience into a competitive esports-level platform with advanced math, multiplayer synchronization, and robust validation.

---

## 🚀 Key Features

### 📐 Advanced Mathematics & Physics
- **Cubic Hermite Spline Interpolation**: Eliminates "snapping" and "jagged" movement. Ghosts move with buttery-smooth precision using velocity-aware curves.
- **Velocity-Based Rendering**: Ghosts calculate their own vectors between 25ms frames for 1:1 realism.
- **Zero-Overhead Physics**: Ghost vehicles are managed locally to ensure the highest server performance.

### 🚥 Multiplayer & Competition
- **Synchronized Grid Starts**: Initiate a professional 3-2-1-GO countdown for all nearby racers with automatic vehicle freezing.
- **Live Ghost Streaming**: Stream your telemetry in real-time to other players on the same track. Race against "Live Ghosts" as if they were real opponents.
- **Recursive Multi-Car Bundling**: Build a full 10-car race by yourself. Chasing a ghost and recording a new lap now "swallows" the old ghost into a single multi-participant replay file.

### 🏗️ Elite Track Builder & Validation
- **Dynamic Property Editor**: Define `Min Speed` and `Allowed Width` for every waypoint.
- **Anti-Cut Engine**: Automated lateral deviation checking and custom Polygon "No-Cut" zones.
- **Progressive Penalty System**: Tiered warnings and time penalties before a lap is invalidated.
- **Auto-Track Analysis**: Tracks are automatically classified (Technical, High Speed, Drag) based on curvature and elevation metrics.

### 🎬 Cinematic & Visuals
- **Prop/Mod Sync**: Ghosts perfectly mirror your vehicle's indicators, sirens, high-beams, and roof state.
- **Passenger Mode**: `/ghostride` into any active ghost to study racing lines from the passenger seat.
- **Solid Visuals**: Customizable opacity (solid 1:1 cars or translucent holograms).

---

## 🛠️ Installation

1. **Requirements**:
   - `ox_lib` (Essential for UI and Notifications)
   - A modern FiveM server build.

2. **Download**:
   ```bash
   git clone https://github.com/your-repo/king-GhostReplay.git
   ```

3. **Setup**:
   - Place inside your `resources` folder.
   - Add `ensure king-GhostReplay` to your `server.cfg`.

---

## 🎮 Usage Guide

### The "Elite" Workflow
1. **Build**: Use `Builder: Setup New Track` to map your course.
2. **Setup Rules**: Click on placed waypoints to set `Min Speed` or `Allowed Width`.
3. **Record**: Start a `QUICK RACE`. Cross the line to begin recording.
4. **Chase & Bundle**: 
   - Go to **Multi-Ghost Manager** -> **Session History**.
   - Select your lap and click **"START CHASE"**.
   - You are now racing your previous car *while* recording a new one!
5. **Multiplayer**: Park 3 cars at the line and use **"MULTIPLAYER GRID START"** to race your friends.

### Commands
- `/trackmenu` - Open the main Elite interface.
- `/ghostride` - Enter Passenger Mode for active ghosts.

---

## 🔧 Technical Details

- **Recording Frequency**: 40Hz (Every 25ms).
- **Serialization**: High-efficiency array-based packing to reduce network payload and file size.
- **Networking**: Event-based "Delta" streaming for Live Ghosts.
- **Storage**: JSON-based flat file storage (standard) with easy hooks for MySQL/PostgreSQL integration.

---

## 📜 License
Dual-licensed under MIT and the Creative Commons Attribution-NonCommercial (CC BY-NC) for the FiveM community.

**Developed with ❤️ for the Kingplayz..**
