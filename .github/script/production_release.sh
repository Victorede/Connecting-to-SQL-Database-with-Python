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

# Extract patterns from RELEASE_NOTES.md (case-insensitive)
branch_patterns=($(grep -io 'bias-[0-9]\+' "$RELEASE_NOTES_FILE" | sort | uniq))

# Verify if any patterns were found
if [ ${#branch_patterns[@]} -eq 0 ]; then
    echo "No branch patterns found in the release notes."
    exit 1
fi

echo "Branch patterns found in release notes: ${branch_patterns[@]}"

# Fetch remote branches
git fetch origin

# Find branches in the remote repository that match the patterns (case-insensitive)
matching_branches=()
for pattern in "${branch_patterns[@]}"; do
    for remote_branch in $(git branch -r | grep -i "$pattern"); do
        # Strip off 'origin/' prefix
        branch_name="${remote_branch#origin/}"
        matching_branches+=("$branch_name")
    done
done

# Remove duplicates
matching_branches=($(echo "${matching_branches[@]}" | tr ' ' '\n' | sort | uniq))

# If no matching branches are found, exit the script
if [ ${#matching_branches[@]} -eq 0 ]; then
    echo "No matching branches found for merging."
    exit 1
fi

echo "Matching branches for merging: ${matching_branches[@]}"

# Create or checkout the release branch and sync with the production branch
git checkout -B $RELEASE_BRANCH
git pull origin $PRODUCTION_BRANCH

# ------------------------------- Squash commit of the matching branches -------------------------------

for branch in "${matching_branches[@]}"; do
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

for branch in "${matching_branches[@]}"; do
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
