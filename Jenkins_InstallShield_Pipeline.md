# Pipeline Jenkins pour la construction d'exécutables InstallShield

## Prérequis

1. **Environnement requis**
   - Jenkins installé et configuré
   - Node InstallShield avec licence valide
   - InstallShield DevStudio ou Professional Edition
   - Environnement Windows (InstallShield n'est pas compatible Linux)
   - Droits administrateur sur le node Jenkins

## Configuration de l'environnement Jenkins

1. **Installation des plugins Jenkins nécessaires**
   - Pipeline Plugin
   - Windows Slaves Plugin
   - Credentials Plugin
   - Version Control Plugin (Git/SVN selon votre cas)

2. **Configuration du node Windows**
   ```groovy
   node {
       // Définition des variables d'environnement
       def INSTALLSHIELD_PATH = "C:\\Program Files (x86)\\InstallShield\\2021"
       def ISCmdBuild = "${INSTALLSHIELD_PATH}\\System\\IsCmdBuild.exe"
   }
   ```

## Structure du Pipeline

```groovy
pipeline {
    agent {
        label 'windows'
    }
    
    environment {
        INSTALLSHIELD_PROJECT = "MonProjet.ism"
        OUTPUT_DIR = "D:\\Builds\\${BUILD_NUMBER}"
        RELEASE_CONFIG = "Release"
    }
    
    stages {
        stage('Préparation') {
            steps {
                // Nettoyage workspace
                cleanWs()
                
                // Récupération du code source
                checkout scm
            }
        }
        
        stage('Validation Projet') {
            steps {
                script {
                    if (!fileExists(env.INSTALLSHIELD_PROJECT)) {
                        error "Fichier projet InstallShield non trouvé"
                    }
                }
            }
        }
        
        stage('Construction') {
            steps {
                script {
                    // Construction de l'installateur
                    bat """
                        "${ISCmdBuild}" -p "${INSTALLSHIELD_PROJECT}" -r "${RELEASE_CONFIG}" \
                        -b "${OUTPUT_DIR}" -c COMP -a BuildModule
                    """
                }
            }
        }
        
        stage('Tests') {
            steps {
                script {
                    // Vérification de la présence du fichier généré
                    if (!fileExists("${OUTPUT_DIR}\\setup.exe")) {
                        error "Build échoué - Executable non généré"
                    }
                }
            }
        }
        
        stage('Archivage') {
            steps {
                // Archivage des artefacts
                archiveArtifacts artifacts: "${OUTPUT_DIR}\\**\\*", fingerprint: true
            }
        }
    }
    
    post {
        always {
            // Nettoyage post-build
            cleanWs()
        }
        success {
            // Notifications en cas de succès
            emailext (
                subject: "Build InstallShield réussi - ${BUILD_NUMBER}",
                body: "Le build ${BUILD_NUMBER} a été généré avec succès",
                recipientProviders: [[$class: 'DevelopersRecipientProvider']]
            )
        }
        failure {
            // Notifications en cas d'échec
            emailext (
                subject: "Échec du build InstallShield - ${BUILD_NUMBER}",
                body: "Le build ${BUILD_NUMBER} a échoué",
                recipientProviders: [[$class: 'DevelopersRecipientProvider']]
            )
        }
    }
}
```

## Configuration des paramètres InstallShield

1. **Options de ligne de commande importantes**
   - `-p` : Chemin du projet InstallShield
   - `-r` : Configuration de release à utiliser
   - `-b` : Répertoire de sortie
   - `-c` : Composants à construire
   - `-a` : Action à effectuer

2. **Bonnes pratiques**
   - Utiliser des variables d'environnement pour les chemins
   - Vérifier la présence des fichiers requis avant la construction
   - Implémenter des tests post-build
   - Archiver les logs de construction
   - Mettre en place des notifications

## Maintenance et dépannage

1. **Logs et diagnostics**
   - Consulter les logs Jenkins dans `${JENKINS_HOME}/jobs/[job_name]/builds/[build_number]/log`
   - Vérifier les logs InstallShield dans le dossier de sortie
   - Activer le mode debug avec l'option `-v` dans IsCmdBuild

2. **Problèmes courants**
   - Droits d'accès insuffisants
   - Chemin d'installation InstallShield incorrect
   - Licence InstallShield non valide ou non trouvée
   - Espace disque insuffisant
