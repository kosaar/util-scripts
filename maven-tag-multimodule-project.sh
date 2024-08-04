#!/bin/bash

# Fonction pour extraire la version du pom.xml
get_pom_version() {
    mvn help:evaluate -Dexpression=project.version -q -DforceStdout
}

# Fonction pour créer un tag dans un répertoire
create_tag_in_directory() {
    local dir=$1
    echo "Traitement du répertoire : $dir"
    
    # Vérifier si le répertoire existe
    if [ ! -d "$dir" ]; then
        echo "Le répertoire $dir n'existe pas. Passage au suivant."
        return
    fi

    # Se déplacer dans le répertoire
    cd "$dir" || return

    # Vérifier si c'est un projet Maven
    if [ ! -f "pom.xml" ]; then
        echo "Pas de fichier pom.xml trouvé dans $dir. Passage au suivant."
        cd - > /dev/null
        return
    fi

    # Récupérer la version actuelle du pom.xml
    VERSION=$(get_pom_version)

    # Vérifier si la version se termine par -SNAPSHOT
    if [[ $VERSION == *-SNAPSHOT ]]; then
        # Supprimer le suffixe -SNAPSHOT pour le tag
        TAG_VERSION=${VERSION%-SNAPSHOT}
    else
        TAG_VERSION=$VERSION
    fi

    # Créer le nom du tag
    TAG_NAME="v$TAG_VERSION"

    # Vérifier si le tag existe déjà
    if git rev-parse "$TAG_NAME" >/dev/null 2>&1; then
        echo "Le tag $TAG_NAME existe déjà dans $dir."
    else
        # Créer le tag
        git tag -a "$TAG_NAME" -m "Release version $TAG_VERSION"

        # Pousser le tag vers le dépôt distant
        git push origin "$TAG_NAME"

        echo "Tag $TAG_NAME créé et poussé avec succès dans $dir."
    fi

    # Retourner au répertoire parent
    cd - > /dev/null
}

# Fonction pour extraire les sous-modules du pom.xml
# get_submodules() {
#     local pom_file=$1
#     xmllint --xpath "//modules/module/text()" "$pom_file" | tr ' ' '\n' | sed '/^$/d'
# }

get_submodules() {
    local pom_file=$1
    grep -oP '(?<=<module>)[^<]+' "$pom_file" | sed 's/^ *//; s/ *$//'
}

# Vérifier si un argument (chemin vers le pom.xml parent) est passé
if [ $# -eq 0 ]; then
    echo "Usage: $0 <chemin/vers/pom.xml>"
    exit 1
fi

parent_pom=$1
parent_dir=$(dirname "$parent_pom")

# Vérifier si le fichier pom.xml existe
if [ ! -f "$parent_pom" ]; then
    echo "Le fichier pom.xml spécifié n'existe pas."
    exit 1
fi

# Obtenir la liste des sous-modules
submodules=$(get_submodules "$parent_pom")

# Traiter chaque sous-module
for module in $submodules; do
    module_path="$parent_dir/$module"
    create_tag_in_directory "$module_path"
done