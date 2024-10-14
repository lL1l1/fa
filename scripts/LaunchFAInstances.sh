#!/bin/bash

# Default parameters
players=${1:-2}  # Default to 2 instances (1 host, 1 client)
map=${2:-"/maps/scmp_009/SCMP_009_scenario.lua"}  # Default map: Seton's Clutch
port=${3:-15000}  # Default port for hosting the game
teams=${4:-2}  # Default to two teams, 0 for FFA

# Path to the game executable (default to Windows path)
gameExecutable="C:/ProgramData/FAForever/bin/FAFDebugger.exe"

# Command-line arguments common for all instances
baseArguments='/init init_dev.lua /EnableDiskWatch /nomovie /RunWithTheWind /gameoptions CheatsEnabled:true'

# Game-specific settings
hostProtocol="udp"
hostPlayerName="HostPlayer"
gameName="MyGame"

# Get the screen resolution using PowerShell, outputting only width and height
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    # Windows environment
    read screenWidth screenHeight < <(powershell -command "Add-Type -AssemblyName System.Windows.Forms; Write-Host \$([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width)\$([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)")
else
    # Linux environment
    screenSize=$(xrandr | grep '*' | awk '{print $1}')
    if [[ -z "$screenSize" ]]; then
        echo "Failed to retrieve screen size automatically."
        read -p "Please enter screen width and height (e.g., 1920 1080): " screenWidth screenHeight
    else
        screenWidth=$(echo $screenSize | cut -d 'x' -f 1)
        screenHeight=$(echo $screenSize | cut -d 'x' -f 2)
    fi
fi

# Output for verification
echo "Screen Width: $screenWidth"
echo "Screen Height: $screenHeight"

# Calculate the number of rows and columns for the grid layout
columns=$(awk "BEGIN {print int(sqrt($players) + 0.9999)}")
rows=$(( players / columns ))

# Calculate the size of each window based on the grid
# Limit the window size to 1024x768 as the game session will not launch if it is smaller
windowWidth=$(( screenWidth / columns ))
windowHeight=$(( screenHeight / rows ))

if [ "$windowWidth" -lt 1024 ]; then
    windowWidth=1024
fi

if [ "$windowHeight" -lt 768 ]; then
    windowHeight=768
fi

# Function to launch a single game instance
launch_game_instance() {
    instanceNumber=$1
    xPos=$2
    yPos=$3
    arguments=$4

    # Add window position and size arguments
    arguments="$arguments /position $xPos $yPos /size $windowWidth $windowHeight"

    # Launch the game instance
    $gameExecutable $arguments &
    echo "Launched instance $instanceNumber at position ($xPos, $yPos) with size ($windowWidth, $windowHeight) and arguments: $arguments"
}

# Function to calculate team argument based on instance number and team configuration
get_team_argument() {
    instanceNumber=$1

    if [ "$teams" -eq 0 ]; then
        echo ""  # No team argument for FFA
        return
    fi
    
    # Calculate team number; additional +1 because player team indices start at 2
    echo "/team $(( (instanceNumber % teams) + 1 + 1 ))"
}

factions=("UEF" "Seraphim" "Cybran" "Aeon")

# Prepare arguments and launch instances
if [ "$players" -eq 1 ]; then
    logFile="dev.log"
    launch_game_instance 1 0 0 "$baseArguments /log $logFile /showlog /map $map"
else
    hostLogFile="host_dev_1.log"
    hostFaction=${factions[RANDOM % ${#factions[@]}]}  # Random faction
    hostTeamArgument=$(get_team_argument 0)
    hostArguments="$baseArguments /log $hostLogFile /showlog /hostgame $hostProtocol $port $hostPlayerName $gameName $map /players $players /$hostFaction $hostTeamArgument"

    # Launch host game instance
    launch_game_instance 1 0 0 "$hostArguments"

    # Client game instances
    for (( i=1; i<players; i++ )); do
        row=$((i / columns))
        col=$((i % columns))
        xPos=$((col * windowWidth))
        yPos=$((row * windowHeight))
        
        clientLogFile="client_dev_$((i + 1)).log"
        clientPlayerName="ClientPlayer_$((i + 1))"
        clientFaction=${factions[RANDOM % ${#factions[@]}]}  # Random faction
        clientTeamArgument=$(get_team_argument $i)
        clientArguments="$baseArguments /log $clientLogFile /joingame $hostProtocol localhost:$port $clientPlayerName /players $players /$clientFaction $clientTeamArgument"
        
        launch_game_instance "$((i + 1))" "$xPos" "$yPos" "$clientArguments"
    done
fi

echo "$players instance(s) of the game launched. Host is running at port $port."
