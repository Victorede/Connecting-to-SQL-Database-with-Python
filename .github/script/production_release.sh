#!/bin/bash

# Configuration
RELEASE_BRANCH="release_branch"
PRODUCTION_BRANCH="production"
EXCLUDE_COMMIT_PATTERN="Merge branch 'main' of" 
RELEASE_NOTES_FILE="RELEASE_NOTES.md" # Path to the RELEASE_NOTES.md file

# Check if RELEASE_NOTES.md exists
if [ ! -f "$RELEASE_NOTES_FILE" ]; then
    echo "Release notes file not found: $RELEASE_NOTES_FILE"
    exit 1
fi

# Extract branch names from RELEASE_NOTES.md
bias_branches=($(grep -o 'bias-[0-9]\+' "$RELEASE_NOTES_FILE" | sort | uniq))

# Verify if any branches were found
if [ ${#bias_branches[@]} -eq 0 ]; then
    echo "No BIAS- branches found in the release notes."
    exit 1
fi

echo "Branches found in release notes: ${bias_branches[@]}"

# Check if the exact branches exist in the remote repository
valid_branches=()
for branch in "${bias_branches[@]}"; do
    if git ls-remote --heads origin | grep -qw "$branch"; then
        valid_branches+=($branch)
    else
        echo "Branch not found in remote: $branch"
    fi
done

# If no valid branches are found, exit the script
if [ ${#valid_branches[@]} -eq 0 ]; then
    echo "No valid branches found for merging."
    exit 1
fi

echo "Valid branches for merging: ${valid_branches[@]}"

# Create or checkout the release branch and sync with the production branch
git checkout -B $RELEASE_BRANCH
git pull origin $PRODUCTION_BRANCH

# ------------------------------- Squash commit of the valid branches -------------------------------

for branch in "${valid_branches[@]}"; do
    # Pull all commits from the branch
    git checkout -B $branch origin/$branch

    # Get the list of commits to exclude
    commits_to_exclude=$(git log --format="%H" --grep="$EXCLUDE_COMMIT_PATTERN")

    # Revert and exclude specific commits
    for commit_to_exclude in $commits_to_exclude; do
        git revert --no-commit $commit_to_exclude
    done

    # Commit the changes as squashed
    git commit -m "Squashed commits for $branch"

    # Push the changes back to the remote branch
    git push origin $branch --force
done

# ------------------------------- Merge the squashed commit to release branch -------------------------------

git checkout $RELEASE_BRANCH

for branch in "${valid_branches[@]}"; do
    remote_branch="origin/$branch"
    
    echo "Merging: $remote_branch"
    read -p "Press Enter to continue..."

    git merge --no-ff --no-edit $remote_branch
done

# Push changes to the remote release branch
git push origin $RELEASE_BRANCH

# Merge the release branch into the production branch
git checkout $PRODUCTION_BRANCH
git merge --no-ff --no-edit $RELEASE_BRANCH

# Push changes to the remote production branch
git push origin $PRODUCTION_BRANCH
