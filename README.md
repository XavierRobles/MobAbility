# Mobability

**Version:** 1.0.0  
**Author:** Waky  
**License:** GNU General Public License v3  
**Link:** [https://github.com/XavierRobles/MobAbility](https://github.com/XavierRobles/MobAbility)

---

## Description (English)

Mobability is an addon for Final Fantasy XI that displays real-time alerts for mob actions in combat according to your selected mode. The addon detects events such as when a mob **starts casting** a spell or **readies** a TP move. Alerts are shown in a floating window using a clear, color-coded system to distinguish the components of each alert:

Mobability is an addon for Final Fantasy XI that displays real-time alerts for mob actions in combat based on the selected alert mode. It detects events such as when a mob starts casting a spell or readies a TP move, and shows the alerts in a floating window where the text appears in colors. This color coding makes it easier to visually identify the important information in each alert, and all settings can be fully customized to suit your preferences.

Mobability operates in two alert modes:
- **Only your current target:** Alerts are generated only for the mob that you have targeted.
- **All party/ally mobs:** Alerts are generated for all mobs attacking any party or allied member.

Additional features include configurable options such as limiting the number of alerts shown, sound notifications, and customizable colors. You can also open the configuration window via the chat command.

### Installation

This addon is distributed as a complete package. Simply copy the Mobability folder into your Ashita addons directory.

### Usage

- **Opening the Configuration:**  
  In Ashita, type `/mb` or `/mobability` in the chat to open the Mobability configuration window.

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

Mobability es un addon para Final Fantasy XI que muestra alertas en tiempo real sobre las acciones de los mobs en combate, basándose en el modo de alerta seleccionado. Detecta eventos como cuando un mob starts casting un hechizo o readies un TP move, y muestra los avisos en una ventana flotante en la que los textos aparecen en colores. Esto permite identificar visualmente la información importante de cada alerta, y la configuración es completamente personalizable para adaptarse a las preferencias del usuario.

Mobability funciona en dos modos de alerta:
- **Solo tu objetivo actual:** Se generan alertas únicamente para el mob que tengas seleccionado.
- **Todos los mobs de party/ally:** Se generan alertas para todos los mobs que estén atacando a algún miembro de la party o aliado.

Entre sus características se incluyen opciones configurables para limitar el número de alertas en pantalla, notificaciones sonoras (si se activan) y personalización de colores. La ventana de configuración se abre escribiendo `/mb` o `/mobability` en el chat de Ashita.

### Instalación

El addon se distribuye como un paquete completo. Copia la carpeta Mobability en el directorio de addons de Ashita.

### Uso

- **Abrir la Configuración:**  
  En Ashita, escribe `/mb` o `/mobability` en el chat para abrir la ventana de configuración de Mobability.

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
      <img src="https://github.com/user-attachments/assets/49fcc87a-8f9a-4057-a11a-cad99cf0a1b0" alt="spell" width="500"/>
    </td>
    <td>
      <img src="https://github.com/user-attachments/assets/fe77af8f-f7da-45b2-8d4a-f9da42896969" alt="mortal ray" width="500"/>
    </td>
  </tr>
  <tr>
    <td colspan="2">
      <img src="https://github.com/user-attachments/assets/7a9b959b-9710-4d25-bc46-9ba467316183" alt="spell chat" width="700"/>
    </td>
  </tr>
</table>

---
