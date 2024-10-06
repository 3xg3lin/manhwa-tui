#!/bin/bash

# Ask the user for the title of the manga
echo "Enter the title of the manga you want to search for:"
read SEARCH_TITLE

# URL encode the manga title (spaces are replaced with %20)
ENCODED_TITLE=$(echo $SEARCH_TITLE | sed 's/ /%20/g')

# Search for manga using the API
SEARCH_RESULTS=$(curl -s "https://api.mangadex.org/manga?title=$ENCODED_TITLE")

# Extract the list of titles from the search results
MANGA_LIST=$(echo $SEARCH_RESULTS | jq -r '.data[] | .id + " " + (.attributes.title.en // "No English Title")')

# Check if any results were found
if [ -z "$MANGA_LIST" ]; then
    echo "No results found for '$SEARCH_TITLE'."
    exit 1
fi

# Present the search results to the user in a select loop
echo "Select a manga from the search results:"

# Create arrays for storing manga IDs and titles
declare -a MANGA_IDS
declare -a MANGA_TITLES
index=0

# Populate the arrays with manga IDs and titles
while read -r line; do
    MANGA_IDS[$index]=$(echo "$line" | awk '{print $1}')
    MANGA_TITLES[$index]=$(echo "$line" | cut -d' ' -f2-)
    ((index++))
done <<< "$MANGA_LIST"

# Display the manga options using the select command
select CHOICE in "${MANGA_TITLES[@]}"; do
    if [ -n "$CHOICE" ]; then
        SELECTED_MANGA_ID=${MANGA_IDS[$REPLY-1]}
        MANGA_NAME=$CHOICE
        echo "You selected: $MANGA_NAME (Manga ID: $SELECTED_MANGA_ID)"
        break
    else
        echo "Invalid choice, try again."
    fi
done

# Create a directory for the manga (replace spaces with underscores)
MANGA_DIR=$(echo "$MANGA_NAME" | sed 's/ /_/g')
mkdir -p "$MANGA_DIR"

# Fetch the chapters of the selected manga
CHAPTERS_JSON=$(curl -s "https://api.mangadex.org/manga/$SELECTED_MANGA_ID/feed")

# Extract chapter number and ID
CHAPTERS_ARRAY=$(echo $CHAPTERS_JSON | jq -c '.data[] | {chapter_number: .attributes.chapter, id: .id}')

# Present the chapters to the user
declare -a CHAPTER_IDS
declare -a CHAPTER_NUMBERS

index=0
echo "Available chapters:"
for CHAPTER in $CHAPTERS_ARRAY; do
    CHAPTER_NUMBER=$(echo "$CHAPTER" | jq -r '.chapter_number')
    CHAPTER_ID=$(echo "$CHAPTER" | jq -r '.id')

    CHAPTER_IDS[$index]=$CHAPTER_ID
    CHAPTER_NUMBERS[$index]=$CHAPTER_NUMBER

    echo "$((index+1)). Chapter $CHAPTER_NUMBER"
    ((index++))
done

# Chapter selection loop
while true; do
    # Ask the user which chapter they want to read
    echo "Enter the chapter number you want to download and read (or 'q' to quit):"
    read SELECTED_CHAPTER_INDEX

    # Quit if the user presses 'q'
    if [[ $SELECTED_CHAPTER_INDEX == "q" ]]; then
        echo "Goodbye!"
        exit 0
    fi

    # Validate if the input is a valid number
    if ! [[ $SELECTED_CHAPTER_INDEX =~ ^[0-9]+$ ]] || [ "$SELECTED_CHAPTER_INDEX" -le 0 ] || [ "$SELECTED_CHAPTER_INDEX" -gt "${#CHAPTER_NUMBERS[@]}" ]; then
        echo "Invalid input, please select a valid chapter number."
        continue
    fi

    # Adjust the index to match array indexing
    REAL_INDEX=$((SELECTED_CHAPTER_INDEX - 1))
    CHAPTER_ID=${CHAPTER_IDS[$REAL_INDEX]}
    CHAPTER_NUMBER=${CHAPTER_NUMBERS[$REAL_INDEX]}

    echo "Downloading chapter $CHAPTER_NUMBER (ID: $CHAPTER_ID)..."

    # Fetch chapter details (including baseUrl, chapter_hash, and page names)
    CHAPTER_INFO=$(curl -s "https://api.mangadex.org/at-home/server/$CHAPTER_ID")
    BASE_URL=$(echo $CHAPTER_INFO | jq -r '.baseUrl')
    CHAPTER_HASH=$(echo $CHAPTER_INFO | jq -r '.chapter.hash')
    PAGES=$(echo $CHAPTER_INFO | jq -r '.chapter.data[]')

    # Create a directory inside the manga folder for the chapter (e.g., chapter_1)
    CHAPTER_DIR="$MANGA_DIR/chapter_$CHAPTER_NUMBER"
    mkdir -p "$CHAPTER_DIR"

    # Download each page of the chapter
    for PAGE in $PAGES; do
        IMAGE_URL="${BASE_URL}/data/${CHAPTER_HASH}/${PAGE}"
        echo "Downloading: $IMAGE_URL"
        wget -q "$IMAGE_URL" -P "$CHAPTER_DIR"
    done

    echo "Download complete for chapter $CHAPTER_NUMBER."

    # Display the images one by one using 'viu'
    echo "Reading chapter $CHAPTER_NUMBER..."

    # List images in ascending order and display one by one
    IMAGES=$(ls "$CHAPTER_DIR" | sort -V)

    for IMAGE in $IMAGES; do
        clear
        viu "$CHAPTER_DIR/$IMAGE"
        echo
        echo "Press Enter to view the next page, or 'q' to quit reading."
        read -r -n 1 key

        # Exit reading if the user presses 'q'
        if [[ $key == "q" ]]; then
            echo "Stopping reading for chapter $CHAPTER_NUMBER."
            break
        fi
    done
done
