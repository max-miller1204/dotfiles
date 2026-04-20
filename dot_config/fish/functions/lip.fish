function lip
    pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+"
    or echo "No active forwards"
end
