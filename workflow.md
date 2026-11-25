# Flujo de Trabajo y Secuencia de Adaptación (`workflow.md`)

Este documento describe paso a paso el flujo seguido para migrar el módulo de comunicación SPI + generador de rampa para el DAC **MCP4921** hacia la plantilla oficial de **Tiny Tapeout para GlobalFoundries 180 nm (`gf180mcuD`)**.

---

## Secuencia de pasos para modificar los archivos

La adaptación de un diseño HDL existente al flujo de Tiny Tapeout debe ejecutarse en el siguiente orden para mantener la coherencia entre el RTL, los metadatos de fabricación, el testbench y los workflows de CI/CD:

1. **Inspección de la plantilla y restricciones de la plataforma**
   - Revisar [`README.md`](README.md), [`info.yaml`](info.yaml), [`src/project.v`](src/project.v), [`src/config.json`](src/config.json), [`test/Makefile`](test/Makefile), [`test/tb.v`](test/tb.v) y los workflows en [`.github/workflows/`](.github/workflows/gds.yaml).
   - Identificar las reglas obligatorias: interfaz fija `tt_um_*`, reset activo en bajo (`rst_n`), todas las salidas y `uio_oe` asignadas, prohibición de modificar claves de `pinout` en `info.yaml`, compatibilidad con Icarus Verilog / Yosys / Verilator linter y soporte para `GL_TEST` (`VPWR`/`VGND`).

2. **Definición del mapeo de pines (Pinout Contract)**
   - Antes de editar el RTL, fijar la asignación de entradas y salidas sobre los pines disponibles de Tiny Tapeout:
     - `ui_in[1:0]` $\rightarrow$ `res_sel[1:0]` (`RES_SEL1`, `RES_SEL0`)
     - `uo_out[0]` $\rightarrow$ `SPI_CS_N`
     - `uo_out[1]` $\rightarrow$ `SPI_SDI`
     - `uo_out[2]` $\rightarrow$ `SPI_SCK`
     - `uo_out[7:3]`, `uio_out[7:0]`, `uio_oe[7:0]` $\rightarrow$ `0`

3. **Adaptación *bottom-up* de los submódulos RTL en `src/`**
   - Migrar primero los módulos hoja que no instancian otros módulos, convirtiendo de SystemVerilog (`.sv`) a Verilog-2001 (`.v`), aplicando `` `default_nettype none `` / `` `default_nettype wire ``, `rst_n` activo en bajo y literales con ancho explícito:
     1. [`src/div_clk.v`](src/div_clk.v) (divisor de reloj `/8` y generador de pulso de desplazamiento)
     2. [`src/shift_reg.v`](src/shift_reg.v) (registro de corrimiento SPI de 16 bits con cabecera `4'b0011`)
     3. [`src/ramp_gen.v`](src/ramp_gen.v) (sincronizador 2-FF, acumulador de 12 bits y enmascaramiento 8/10/12 bits)
     4. [`src/control.v`](src/control.v) (FSM de 4 estados codificada en Gray para evitar glitches en `cs_n`)

4. **Integración en el wrapper top-level (`src/project.v`)**
   - Renombrar el módulo superior a `tt_um_oscarc_507_mcp4921_spi` (respetando el prefijo `tt_um_`).
   - Instanciar `m0_control`, `m1_div_clk`, `m2_ramp_gen` y `m3_shift_reg`.
   - Conectar `ui_in[1:0]` y `uo_out[2:0]`, fijar a `0` las salidas sin usar y reunir las entradas no usadas en `wire _unused`.

5. **Actualización del manifiesto del proyecto (`info.yaml`) y revisión de `src/config.json`**
   - Actualizar `title`, `author`, `description`, `clock_hz` (`50000000`), `tiles` (`"1x1"`) y `top_module` (`"tt_um_oscarc_507_mcp4921_spi"`).
   - Listar los 5 archivos en `source_files` dentro de [`info.yaml`](info.yaml) exactamente como aparecen en `src/`.
   - Llenar los nombres de pines usados en `pinout` sin agregar ni eliminar ninguna de las 24 claves originales ni alterar `yaml_version: 6`.
   - Verificar en [`src/config.json`](src/config.json) que `CLOCK_PERIOD` (`20` ns = 50 MHz), `CLOCK_PORT` (`"clk"`) y `RUN_LINTER` (`1`) sean consistentes con el diseño.

6. **Adaptación del entorno de simulación y testbenches (`test/`)**
   - Actualizar `PROJECT_SOURCES` en [`test/Makefile`](test/Makefile) para reflejar los 5 archivos `.v` en `src/`.
   - Actualizar el nombre del DUT en [`test/tb.v`](test/tb.v) preservando `` `ifdef GL_TEST `` y agregar el monitor pasivo SPI Modo (0,0) usando únicamente puertos externos.
   - Portar la lógica de verificación de `top_tb.sv` a pruebas automáticas en [`test/test.py`](test/test.py) con `cocotb` (reset, barrido completo de rampas de 8/10/12 bits, verificación de cabecera `4'b0011`, conteo de 16 flancos `SCK` y cambio dinámico de resolución).
   - Actualizar [`test/tb.gtkw`](test/tb.gtkw) con las señales del monitor SPI para inspección en GTKWave/Surfer.

7. **Actualización de documentación (`docs/info.md` y `README.md`)**
   - Completar [`docs/info.md`](docs/info.md) con las secciones `How it works`, `How to test` y `External hardware` para la generación automática del datasheet de Tiny Tapeout.
   - Actualizar [`README.md`](README.md) con el resumen del proyecto, pinout y enlaces a la documentación.

8. **Verificación local y validación en GitHub Actions**
   - Compilar y simular localmente el módulo `tt_um_oscarc_507_mcp4921_spi` y `test/tb.v`, validar sintaxis de `test/test.py` y consistencia de `info.yaml`.
   - Al hacer `git push` a GitHub, el repositorio dispara automáticamente:
     - [`.github/workflows/test.yaml`](.github/workflows/test.yaml): simulación RTL con `iverilog` + `cocotb`.
     - [`.github/workflows/docs.yaml`](.github/workflows/docs.yaml): validación y construcción del datasheet desde `docs/info.md` e `info.yaml`.
     - [`.github/workflows/gds.yaml`](.github/workflows/gds.yaml): síntesis, P&R y generación de GDSII con LibreLane para `gf180mcuD`, seguido de `precheck`, simulación *gate-level* (`gl_test` con `GATES=yes`) y publicación del visor 3D/2D.
