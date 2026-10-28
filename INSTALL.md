# INSTALL

1. Instala Docker Desktop y ábrelo.
2. Ciérralo desde el icono de la ballena → Quit. En la terminal:

```
sudo /Applications/Docker.app/Contents/MacOS/install vmnetd
```

Instala el ayudante que deja a Docker abrir el puerto 80. Ábrelo otra vez.

3. En `~/.zshrc`, o en `~/.zprofile`, o si usas bash en `~/.bash_profile`. La carpeta donde está `lar`:

```
export PATH="/ruta/de/lar:$PATH"
```

Hace que `lar` se encuentre desde cualquier carpeta. Abre una terminal nueva.

4. Docker Desktop → Settings → Resources → File sharing. Tienen que estar la carpeta `data/` de este proyecto y cada `path` y `public_path` de `data/config/sites.yaml`. Con Docker cerrado, `lar install` puede añadirlas. Si está abierto, ciérralo, ejecuta `lar install` y ábrelo.

`lar install` comprueba Docker, `vmnetd` y esas carpetas compartidas.

5. `lar init` crea `settings.yaml`, `sites.yaml` y `data/.env` si no existen. Si ya tienen contenido, `lar install` no los pisa salvo que respondas sí al PELIGRO.

6. `lar up` arranca el entorno y escribe los dominios en `/etc/hosts`. macOS pide la contraseña si el bloque cambia. `lar down` para el entorno y quita ese bloque.

7. `lar -s site1` abre la shell de ese sitio desde cualquier carpeta.
