# Mobability

**Version:** 1.0.2  
**Author:** Waky  
**License:** GNU General Public License v3  
**Link:** [https://github.com/XavierRobles/MobAbility](https://github.com/XavierRobles/MobAbility)

---

## 📌 Changelog

### v1.0.2 (English)

- Fixed an issue where names were not displayed correctly in certain cases.
- Fixed an issue where mob self-targeted actions did not display the name properly.
- Names now display correctly even when the action's target is not part of the party or alliance.
- Fixed an issue where pet names were not displayed when they received an action.
- Added the summoner's name to the pet information.
- Added alerts for mobs using two-hour (2H) abilities.
- Added configurable background for alerts in the options menu.
- Fixed an issue where player-defined settings were not being saved correctly.
- Documented the code for better readability and maintenance.

---

### v1.0.2 (Español)

- Se corrigió un error donde los nombres no se mostraban correctamente en ciertos casos.
- Se corrigió un error al mostrar acciones que un mob se hacía a sí mismo.
- Ahora los nombres se muestran correctamente incluso si el objetivo de la acción no está en la party o alianza.
- Se corrigió un error donde no se mostraban los nombres de los pets al recibir una acción.
- Se añadió el nombre del invocador en la información del pet.
- Se añadieron alertas para detectar habilidades 2H de los mobs.
- Se añadió un fondo configurable en las alertas desde el menú de opciones.
- Se corrigió un problema donde no se guardaban correctamente los ajustes definidos por el jugador.
- Se documentó el código para mejorar su legibilidad y mantenimiento.

---

### v1.0.1

---

## Description (English)

Mobability is an addon for Final Fantasy XI that displays real-time alerts for mob actions in combat based on your selected alert mode. The addon detects events such as when a mob begins to cast a spell or performs a TP move, and shows the alerts in a floating window. The notifications appear in different colors, which help differentiate between:

- The mob's name.
- The action performed (spell or TP move).
- The target of the action.

Mobability operates in two alert modes:
- **Only your current target:** Alerts are generated only for the mob that you have targeted.
- **All party/ally mobs:** Alerts are generated for all mobs attacking any party or allied member.

Additional features include configurable options such as limiting the number of alerts shown, sound notifications, and customizable colors. You can also open the configuration window via the chat command.

### Installation

1. **Step 1:**  
   Copy the `Mobability` folder into the Ashita addons directory or into the game client folder. For example:  
   `HorizonXI\Game\addons`

2. **Step 2:**  
   - **Automatic Loading:**  
     To have the addon load automatically when the game starts, open the `default.txt` file located in the `scripts` folder and add the following line in the addons section or at the end of the file:  
     ```
     /addon load mobability
     ```
   - **Manual Loading:**  
     To load the addon manually in-game, type the following command in chat:  
     ```
     /addon load mobability
     ```

Following these steps will load the addon so you can start using it.

### Usage

- **Opening the Configuration:**  
In game, type `/mb` or `/mobability` in the chat to open the Mobability configuration window.


- **Floating Alerts:**  
  Alerts will automatically appear on-screen during combat for up to 10 seconds (or until the action finishes).

- **Alert Modes:**
  - **Only your current target:** Displays alerts only for the mob you are targeting.
  - **All party/ally mobs:** Displays alerts for all mobs attacking any party or allied member.

- **Sound Notifications:**  
  When enabled, a distinct sound is played for spells and TP moves.

<table>
  <tr>
    <td style="vertical-align: top; padding-right: 10px;">
      <h3>Configuration</h3>
      <p>
        In the configuration window you can:<br>
        - Adjust the position and text size.<br>
        - Set the maximum number of alerts to display (recommended: 5; set to 0 for unlimited).<br>
        - Choose the alert mode: <strong>"Only your current target"</strong> or <strong>"All party/ally mobs"</strong>.<br>
        - Enable or disable alerts in the chat.<br>
        - Enable or disable sound notifications.<br>
        - Customize the colors for:<br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Mob Name</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Fixed Message Text</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Spell Action</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>TP Move Action</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Target Name</strong><br>
        - Test your settings with the "Test Alert" button.
      </p>
      <p>All settings are saved automatically when you close the configuration window.</p>
    </td>
    <td style="vertical-align: top;">
      <img src="https://github.com/user-attachments/assets/3c649393-b5de-4935-9663-cfe3327d34ee" alt="config mobability" width="300"/>
    </td>
  </tr>
</table>



### Additional Notes

- **Compatibility:**  
  Mobability has been designed for Ashita, aiming to enhance your combat experience in Final Fantasy XI with clear and configurable alerts.

- **Server:**  
  This addon is optimized for private servers of FFXI, and is especially designed for Horizonxi ([https://horizonxi.com/](https://horizonxi.com/)). It has not been tested on the Retail version.

- **License:**  
  Mobability is distributed under the GNU General Public License v3.

---

## Descripción (Español)

Mobability es un addon para Final Fantasy XI que muestra alertas en tiempo real sobre las acciones de los mobs durante el combate, en función del modo de alerta que selecciones. El addon detecta eventos, por ejemplo, cuando un mob empieza a lanzar un hechizo o ejecuta un movimiento especial (TP move), y muestra las alertas en una ventana flotante. Los avisos se presentan en distintos colores, lo que facilita distinguir entre: 

- El nombre del mob.
- La acción que realiza (hechizo o TP move).
- El objetivo o receptor de la acción.

Mobability funciona en dos modos de alerta:
- **Solo tu objetivo actual:** Se generan alertas únicamente para el mob que tengas seleccionado.
- **Todos los mobs de party/ally:** Se generan alertas para todos los mobs que estén atacando a algún miembro de la party o aliado.

Entre sus características se incluyen opciones configurables para limitar el número de alertas en pantalla, notificaciones sonoras (si se activan) y personalización de colores. La ventana de configuración se abre escribiendo `/mb` o `/mobability` en el chat de Ashita.

### Instalación

1. **Paso 1:**  
   Copia la carpeta `Mobability` en el directorio de addons de Ashita o en la carpeta del cliente del juego. Por ejemplo:  
   `HorizonXI\Game\addons`

2. **Paso 2:**  
   - **Carga automática:**  
     Para que el addon se ejecute automáticamente al iniciar el juego, abre el archivo `default.txt` que se encuentra en la carpeta `scripts` y añade la siguiente línea en la sección de addons o al final del archivo:  
     ```
     /addon load mobability
     ```
   - **Carga manual:**  
     Dentro del juego, abre el chat y escribe:  
     ```
     /addon load mobability
     ```

Con estos pasos, el addon se cargará y estará listo para usar.

### Uso

- **Abrir la Configuración:**  
  En el juego, escribe `/mb` o `/mobability` en el chat para abrir la ventana de configuración de Mobability.

- **Alertas Flotantes:**  
  Las alertas se mostrarán automáticamente en combate y permanecerán en pantalla hasta 10 segundos (o hasta que la acción finalice).

- **Modos de Alerta:**
  - **Solo tu objetivo actual:** Muestra alertas únicamente para el mob que tienes seleccionado.
  - **Todos los mobs de party/ally:** Muestra alertas para todos los mobs que estén atacando a la party o aliados.

- **Notificaciones Sonoras:**  
  Si están habilitadas, se reproducirá un sonido distinto para los hechizos y los TP moves.

<table>
  <tr>
    <td style="vertical-align: top; padding-right: 10px;">
      <h3>Configuración</h3>
      <p>
        En la ventana de configuración puedes:<br>
        - Ajustar la posición y el tamaño del texto.<br>
        - Establecer el número máximo de alertas a mostrar (recomendado: 5; pon 0 para ilimitado).<br>
        - Elegir el modo de alerta: <strong>"Sólo tu objetivo actual"</strong> o <strong>"Todos los mobs de party/ally"</strong>.<br>
        - Activar o desactivar las alertas en el chat.<br>
        - Activar o desactivar las notificaciones de sonido.<br>
        - Personalizar los colores para:<br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Nombre del mob</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Texto fijo del mensaje</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Acción de hechizo</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Acción de TP Move</strong><br>
          &nbsp;&nbsp;&nbsp;&bull; <strong>Nombre del receptor</strong><br>
        - Probar la configuración con el botón "Alerta de prueba".
      </p>
      <p>Todos los ajustes se guardan automáticamente al cerrar la ventana de configuración.</p>
    </td>
    <td style="vertical-align: top;">
      <img src="https://github.com/user-attachments/assets/3c649393-b5de-4935-9663-cfe3327d34ee" alt="config mobability" width="300"/>
    </td>
  </tr>
</table>

### Notas Adicionales

- **Compatibilidad:**  
  Mobability ha sido diseñado para funcionar con Ashita y mejorar la experiencia de combate en Final Fantasy XI mediante alertas claras y configurables.

- **Servidor:**  
  Este addon está optimizado para servidores privados de FFXI, especialmente para Horizonxi ([https://horizonxi.com/](https://horizonxi.com/)). No ha sido probado en el entorno Retail.


- **Licencia:**  
  Mobability se distribuye bajo la GNU General Public License v3.

<table>
  <tr>
    <td>
      <img src="https://github.com/user-attachments/assets/e5b261e8-8105-46f1-812f-ac18a28bf8da" alt="spell" width="500"/>
    </td>
    <td>
      <img src="https://github.com/user-attachments/assets/366b1aa4-43c1-42c7-b42b-1e2d99db1463" alt="mortal ray" width="500"/>
    </td>
  </tr>
  <tr>
    <td colspan="2">
      <img src="https://github.com/user-attachments/assets/7a9b959b-9710-4d25-bc46-9ba467316183" alt="spell chat" width="700"/>
    </td>
  </tr>
</table>

---
