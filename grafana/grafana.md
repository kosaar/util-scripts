Pour configurer l'authentification LDAP dans Grafana Community Edition, suivez ces étapes :

1. **Activer LDAP dans le fichier de configuration de Grafana** :
    - Ouvrez le fichier de configuration principal de Grafana, généralement situé à `/etc/grafana/grafana.ini`.
    - Activez l'authentification LDAP en ajoutant ou en modifiant les lignes suivantes sous la section `[auth.ldap]` :
      ```ini
      [auth.ldap]
      enabled = true
      config_file = /etc/grafana/ldap.toml
      allow_sign_up = true
      ```

2. **Configurer le fichier `ldap.toml`** :
    - Créez ou éditez le fichier `ldap.toml` à l'emplacement spécifié dans `grafana.ini`.
    - Ajoutez les paramètres de configuration LDAP. Voici un exemple de configuration de base :
      ```toml
      [[servers]]
      host = "ldap.example.com"
      port = 389
      use_ssl = false
      start_tls = false
      ssl_skip_verify = false
      bind_dn = "cn=admin,dc=example,dc=com"
      bind_password = 'admin_password'
      search_filter = "(cn=%s)"
      search_base_dns = ["dc=example,dc=com"]
      ```

3. **Configurer les mappages de groupes (facultatif)** :
    - Si vous souhaitez mapper des groupes LDAP à des rôles Grafana, ajoutez des mappages de groupes dans le fichier `ldap.toml` :
      ```toml
      [[servers.group_mappings]]
      group_dn = "cn=grafana_admins,dc=example,dc=com"
      org_role = "Admin"
 
      [[servers.group_mappings]]
      group_dn = "cn=grafana_editors,dc=example,dc=com"
      org_role = "Editor"
      ```

4. **Redémarrer Grafana** :
    - Après avoir modifié les fichiers de configuration, redémarrez Grafana pour appliquer les changements.

5. **Tester la configuration** :
    - Vous pouvez tester la connexion LDAP via l'interface utilisateur de Grafana pour vous assurer que tout fonctionne correctement.

Pour plus de détails, vous pouvez consulter la documentation officielle de Grafana sur la configuration de l'authentification LDAP : [Configuration LDAP](https://grafana.com/docs/grafana/latest/auth/ldap/).