import os
from pathlib import Path

def get_directory_structure(path=".", prefix="", ignore_dirs={'.git', 'node_modules', '__pycache__', '.next', 'dist', 'build'}):
    """Generate directory structure with file size indicators"""
    
    path = Path(path)
    if not path.is_dir():
        return []
    
    items = []
    contents = list(path.iterdir())
    contents.sort(key=lambda x: (not x.is_dir(), x.name.lower()))
    
    for i, item in enumerate(contents):
        if item.name.startswith('.') and item.name not in {'.env.example', '.gitignore'}:
            continue
            
        if item.is_dir() and item.name in ignore_dirs:
            continue
            
        is_last = i == len(contents) - 1
        current_prefix = "└── " if is_last else "├── "
        next_prefix = prefix + ("    " if is_last else "│   ")
        
        if item.is_file():
            size = item.stat().st_size
            if size == 0:
                items.append(f"{prefix}{current_prefix}{item.name} (EMPTY)")
            else:
                items.append(f"{prefix}{current_prefix}{item.name} ()")
        else:
            items.append(f"{prefix}{current_prefix}{item.name}/")
            items.extend(get_directory_structure(str(item), next_prefix, ignore_dirs))
    
    return items

# Run the extraction - use current directory "."
print("Project Structure:")
print("=" * 50)
structure = get_directory_structure(".")
for line in structure:
    print(line)

# List only empty files
print("\n" + "=" * 50)
print("Empty Files:")
print("=" * 50)
empty_count = 0
for root, dirs, files in os.walk("."):
    # Skip unwanted directories
    dirs[:] = [d for d in dirs if d not in {'.git', 'node_modules', '__pycache__', '.next', 'dist', 'build'}]
    for file in files:
        filepath = os.path.join(root, file)
        if os.path.getsize(filepath) == 0:
            print(f"  - {filepath}")
            empty_count += 1

if empty_count == 0:
    print("  No empty files found")
else:
    print(f"\nTotal: {empty_count} empty files")