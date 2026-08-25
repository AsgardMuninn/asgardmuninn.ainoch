# CONTENT_SPEC — Modo texto libre (Type something)

**Feature solicitada por el usuario:**
"Cuando le dé a 'type something' se oculten las opciones y se expanda un input
de texto ocupando el espacio donde antes estaban las opciones. Que sea fluido
también modificando el mismo elemento para que se sienta neat."

## Requisitos

1. **Disparador**: hacer clic en la opción de texto libre ("Type something") del
   estado expandido activa el modo texto.
2. **Transformación fluida del MISMO contenedor**: las opciones (OptionRowView)
   se ocultan y un input de texto expande en el MISMO espacio (misma altura,
   mismo bloque `VStack` de opciones). Transición con `withAnimation` + 
   `.transition(.opacity + .scale)` — NO dos layouts distintos que salten.
3. **El input**:
   - Ocupa el espacio que antes tenían las opciones (height = bloque de opciones).
   - Placeholder claro ("Escribí tu respuesta libre…").
   - Recibe el FOCO automáticamente al activarse (NSTextField first responder).
   - Estilo oscuro: fondo en escala de grises, texto blanco, cornerRadius 10 —
     coherente con `OptionRowView`.
4. **Enviar**: `Return` o botón "Enviar" → envía el texto al pane activo
   (`herdr agent prompt <pane> <text>`), cierra el modo texto y descarta el
   evento (dismiss) — el harness recibe la respuesta libre.
5. **Cancelar**: `Esc` (o el botón Descartar que ya existe) → vuelve a las
   opciones sin enviar.
6. **No romper nada**: la geometría/transición del notch (TRANSITION_SPEC),
   el hover global y el click-through quedan intactos.

## Estado del modelo

```
@Published textInputActive: Bool      // true = modo texto
@Published textInputValue: String     // buffer del input
```

## Lógica de transición (función pura, testeable)

```
onOptionTap(optionIndex, optionTitle):
   if isFreeTextOption(optionTitle):  -> entrar modo texto (textInputActive=true)
   else:                              -> enviar número de opción (comportamiento actual)

isFreeTextOption(title): title lowercased contiene "type" o "something"
   (la opción "4. Type something." del harness pi)

onTextSubmit(text):
   if text.trim != "" -> enviar al pane + dismiss (fin de la interacción)
   else               -> no hacer nada (no enviar vacío)

onTextCancel():                        // Esc
   textInputActive = false             // volver a las opciones, sin enviar
```

## Verificación

- Test puro de `isFreeTextOption` (detección correcta).
- Test puro del flujo `onOptionTap` → entra/sale de modo texto según la opción.
- Runtime: al hacer clic "Type something" el input aparece con foco; al enviar
  texto el harness lo recibe (log `AINOCH: freeText`); Esc vuelve a opciones.

## Mejoras (req 2 — click fuera + foco real)

### 2a. Click FUERA del campo de texto → vuelve a opciones (cancel implícito)

Si el usuario hace clic en cualquier parte de la isla fuera del TextField
(pregunta, header, márgenes), el modo texto se desactiva y se vuelven a mostrar
las opciones (transición inversa, sin enviar). Se implementa con un fondo
transparente (`contentShape`) que captura el tap cuando `textInputActive`.

Lógica pura (testeable):

```
onTapOutside(textInputActive = true)  → salir del modo texto (cerrar sin enviar)
onTapOutside(textInputActive = false) → no hace nada (opciones visibles)
```

Cualquier otra acción de la vista (tocar una opción real, Enviar, Descartar) no
es "fuera" — solo el fondo/intersticio lo es.

### 2b. Se habilita la ENTRADA DE TEXTO (foco real)

**CAUSA RAÍZ**: `NotchWindow.canBecomeKey = false` (requisito para no robar el
foco al desktop / no molestar). Pero un NSPanel que no puede ser key NUNCA
entrega el teclado al TextField → no se puede escribir.

**REQUISITO**: cuando el modo texto está activo, la ventana debe poder ser key
(solo entonces):
- `canBecomeKey` retorna `true` sólo cuando `textInputActive == true`.
- Al activar el modo texto: `window.makeKey()` + `window.makeFirstResponder(
  fieldEditor)` + activar la app.
- Al salir del modo texto (enviar/click fuera/Descartar): restaurar
  `canBecomeKey = false` para no volver a robar el foco.

Como el panel vive en una app `.accessory`, `NSApp.activate(ignoringOtherApps: true)`
es necesario para que el teclado llegue al campo mientras se escribe.
