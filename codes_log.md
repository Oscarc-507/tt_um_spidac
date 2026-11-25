# Registro de Cambios en el Código (`codes_log.md`)

Este documento detalla todas las modificaciones realizadas para adaptar el diseño original en SystemVerilog del generador de rampa SPI para el DAC **MCP4921** (`control.sv`, `div_clk.sv`, `ramp_gen.sv`, `shift_reg.sv`, `top.sv`, `top_tb.sv`) a las convenciones, restricciones de síntesis/linting y entorno de verificación de **Tiny Tapeout (`gf180mcuD`)**.

---

## 1. Cambios globales transversales

| Aspecto | Diseño original (`.sv`) | Diseño adaptado (`.v` Tiny Tapeout) | Justificación |
| :--- | :--- | :--- | :--- |
| **Lenguaje HDL** | SystemVerilog (`logic`, `always_ff`, `always_comb`, `typedef enum`) | **Verilog-2001** (`wire`, `reg`, `always @(...)`, `localparam`) | Compatibilidad directa sin flags extra con `iverilog` (CI `test.yaml` y `gl_test`), Yosys (`gds.yaml`, `fpga.yaml`) y Verilator linter (`RUN_LINTER: 1`). |
| **Chequeo de redes implícitas** | No declarado | `` `default_nettype none `` al inicio y `` `default_nettype wire `` al final | Previene cables implícitos por errores tipográficos y evita propagar `none` hacia archivos posteriores (ej. netlists gate-level). |
| **Polaridad del reset** | `rst` activo en alto (`posedge rst`, `if (rst)`) | `rst_n` activo en bajo (`negedge rst_n`, `if (!rst_n)`) | Estándar obligatorio de la interfaz de Tiny Tapeout y mapeo directo a flip-flops con reset asíncrono activo en bajo de `gf180mcu_fd_sc_mcu7t5v0`. |
| **Literales con ancho explícito** | `'0`, `'1`, `1'b1` en sumadores | `2'd0`, `2'd1`, `2'd3`, `3'd0`, `3'd1`, `4'd0`, `4'd1`, `16'd0` | Elimina advertencias de truncamiento/expansión (`WIDTH`) en el linter de Verilator dentro de LibreLane. |
| **Licencia y cabecera** | Sin cabecera uniforme | Cabecera SPDX `Apache-2.0` | Requisito recomendado de los repositorios plantilla de Tiny Tapeout. |

---

## 2. Mapeo de archivos: origen vs. destino

| Archivo original | Archivo adaptado | Acción principal |
| :--- | :--- | :--- |
| `control.sv` | [`src/control.v`](src/control.v) | Conversión a Verilog-2001, `rst_n`, codificación Gray y salida `cs_n` libre de glitches. |
| `div_clk.sv` | [`src/div_clk.v`](src/div_clk.v) | Conversión a Verilog-2001, `rst_n` y literales de 3 bits. |
| `ramp_gen.sv` | [`src/ramp_gen.v`](src/ramp_gen.v) | Conversión a Verilog-2001, `rst_n` y eliminación de bloque comentado duplicado. |
| `shift_reg.sv` | [`src/shift_reg.v`](src/shift_reg.v) | Conversión a Verilog-2001, `rst_n` y literales explícitos de 4 y 16 bits. |
| `top.sv` | [`src/project.v`](src/project.v) | Reemplazo por wrapper `tt_um_oscarc_507_mcp4921_spi` con puertos estándar y amarre de pines no usados. |
| `top_tb.sv` | [`test/tb.v`](test/tb.v) + [`test/test.py`](test/test.py) | Separación en wrapper Verilog compatible con `GL_TEST` y pruebas automatizadas en `cocotb`. |
| *(Nuevo en plantilla)* | [`test/Makefile`](test/Makefile), [`test/tb.gtkw`](test/tb.gtkw), [`info.yaml`](info.yaml) | Registro de fuentes, metadatos del shuttle GF180nm, pinout y señales de onda. |

---

## 3. Detalle de cambios por módulo

### 3.1. [`src/control.v`](src/control.v) (antes `control.sv`)
- **Reset:** `input logic rst` cambiado a `input wire rst_n`; sensibilidad cambiada a `always @(posedge clk or negedge rst_n)` con `if (!rst_n)`.
- **Nombre de Chip Select:** `cs` renombrado internamente a `cs_n` para dejar explícita su polaridad activa en bajo en el protocolo SPI del MCP4921.
- **Codificación Gray de la FSM (mejora para silicio real y `GL_TEST`):**
  - En `control.sv`, `typedef enum logic [2:0] { IDLE, START, SEND, WAIT }` asignaba codificación binaria secuencial (`000`, `001`, `010`, `011`) y calculaba `assign cs = !(state == START || state == SEND);`. En transición `START (001) -> SEND (010)` cambian 2 bits simultáneamente, lo que puede generar un *glitch* combinacional en `cs` durante simulaciones *gate-level* con retardos unitarios (`#1`) o en silicio.
  - En `src/control.v`, los estados usan codificación Gray de 2 bits:
    ```verilog
    localparam [1:0] IDLE  = 2'b00; // cs_n = 1
    localparam [1:0] START = 2'b01; // cs_n = 0
    localparam [1:0] SEND  = 2'b11; // cs_n = 0
    localparam [1:0] WAIT  = 2'b10; // cs_n = 1

    assign cs_n    = ~state[0];
    assign div_en  = (state == SEND);
    assign ramp_en = (state == WAIT) && (cont_clk == 2'd3);
    ```
  - De este modo `cs_n` depende únicamente de un solo bit de flip-flop (`state[0]`), manteniendo la funcionalidad exacta ciclo a ciclo sin riesgos de transición.
- **Aritmética:** `cont_clk <= cont_clk + 1'b1;` reemplazado por `cont_clk <= cont_clk + 2'd1;`, y `'1` por `2'd3`.

### 3.2. [`src/div_clk.v`](src/div_clk.v) (antes `div_clk.sv`)
- **Tipos y bloques:** `logic` -> `wire` / `reg`; `always_ff @(posedge clk, posedge rst)` -> `always @(posedge clk or negedge rst_n)`.
- **Literales:** `'0` -> `3'd0`; `cont + 1'b1` -> `cont + 3'd1`.
- **Comportamiento:** Se conserva exactamente la división por 8 (`sck = cont[2]`) y el pulso de desplazamiento (`pulse = en && (cont == 3'd7)`).

### 3.3. [`src/ramp_gen.v`](src/ramp_gen.v) (antes `ramp_gen.sv`)
- **Limpieza de código:** Se eliminaron las líneas 48–97 del archivo original que contenían una copia comentada del propio módulo.
- **Sincronizador y acumulador:** `always_ff @(posedge clk or posedge rst)` cambiado a `always @(posedge clk or negedge rst_n)` con `if (!rst_n)`. Se mantiene el valor inicial tras reset en modo de 12 bits (`2'b10`) en el sincronizador de 2 flip-flops (`res_ff1`, `res_sync`) y `count <= 12'd0`.
- **Bloques combinacionales:** `always_comb` reemplazado por `always @(*)`; `output logic [11:0] dac_data` convertido a `output reg [11:0] dac_data`.

### 3.4. [`src/shift_reg.v`](src/shift_reg.v) (antes `shift_reg.sv`)
- **Parámetro local:** `localparam logic [3:0] CONFIG_DATA = 4'b0011;` cambiado a `localparam [3:0] CONFIG_DATA = 4'b0011;`.
- **Reset y carga:** `always_ff @(posedge clk, posedge rst)` convertido a `always @(posedge clk or negedge rst_n)` con `if (!rst_n)`. Literales `'0` reemplazados por `16'd0` y `4'd0`.
- **Comportamiento:** Se conserva la carga paralela `{CONFIG_DATA, data}` mientras `!en` y el desplazamiento MSB-primero en cada `pulse`, con `done = en && pulse && (cont_bits == 4'd15)`.

### 3.5. [`src/project.v`](src/project.v) (antes `top.sv`)
- **Nombre del módulo:** Renombrado de `top` a `tt_um_oscarc_507_mcp4921_spi` (prefijo obligatorio `tt_um_`).
- **Interfaz estándar de Tiny Tapeout:**
  - Puertos originales (`clk`, `rst`, `sck`, `sdi`, `cs`, `res[1:0]`) sustituidos por la firma fija:
    `ui_in[7:0]`, `uo_out[7:0]`, `uio_in[7:0]`, `uio_out[7:0]`, `uio_oe[7:0]`, `ena`, `clk`, `rst_n`.
- **Mapeo de pines e inmovilización de pines no usados:**
  - `ui_in[1:0]` conectado a `.res_sel(ui_in[1:0])` de `m2_ramp_gen`.
  - `uo_out = {5'b00000, sck, sdi, cs_n}` (`uo_out[0] = cs_n`, `uo_out[1] = sdi`, `uo_out[2] = sck`, `uo_out[7:3] = 0`).
  - Pines bidireccionales deshabilitados como salida: `uio_out = 8'b0000_0000` y `uio_oe = 8'b0000_0000`.
  - Señales de entrada sin usar agrupadas en `wire _unused = &{ena, ui_in[7:2], uio_in, 1'b0};` para evitar advertencias del linter.

### 3.6. [`test/tb.v`](test/tb.v) y [`test/test.py`](test/test.py) (antes `top_tb.sv`)
- **Wrapper Verilog [`test/tb.v`](test/tb.v):**
  - Instancia `tt_um_oscarc_507_mcp4921_spi user_project` preservando el bloque `` `ifdef GL_TEST `` (`.VPWR(VPWR)`, `.VGND(VGND)`) requerido por la simulación *gate-level* de `gf180mcuD`.
  - Expone alias externos (`res_sel`, `spi_cs_n`, `spi_sdi`, `spi_sck`) y conserva el monitor pasivo SPI Modo (0,0) (`spi_rx_shift`, `dac_cfg_rx`, `dac_code_rx`) conectado únicamente a los pines externos de `user_project` y `rst_n` (sin acceder a jerarquía interna, garantizando compatibilidad con `GL_TEST`).
- **Suite `cocotb` [`test/test.py`](test/test.py):**
  - Reemplaza la generación de estímulos imperativa de `top_tb.sv` por pruebas automatizadas y auto-verificables (`assert`) con reloj de 50 MHz (`unit="ns"`):
    1. `test_reset_and_idle`: verifica estado de reset (`spi_cs_n == 1`, `spi_sck == 0`) y que `uo_out[7:3]`, `uio_out`, `uio_oe` permanezcan en `0`.
    2. `test_ramp_resolutions`: valida los modos `2'b00` (8 bits, 260 tramas), `2'b01` (10 bits, 1030 tramas en RTL / 32 en `GATES=yes`), `2'b10` (12 bits, 4100 tramas en RTL / 32 en `GATES=yes`) y `2'b11` (12 bits, 16 tramas), comprobando 16 flancos de subida de `SCK` por trama, `cfg == 4'b0011` y el código de 12 bits exacto.
    3. `test_dynamic_resolution_switch`: verifica el cambio dinámico de `ui_in[1:0]` sin reiniciar (`rst_n = 1`) y el correcto enmascaramiento de LSBs tras la sincronización de 2 ciclos.
- **[`test/Makefile`](test/Makefile) y [`test/tb.gtkw`](test/tb.gtkw):**
  - `PROJECT_SOURCES` actualizado a `project.v control.v div_clk.v ramp_gen.v shift_reg.v`.
  - `tb.gtkw` actualizado a las señales externas de `tb` (`spi_cs_n`, `spi_sck`, `spi_sdi`, `dac_cfg_rx`, `dac_code_rx`).

### 3.7. [`info.yaml`](info.yaml), [`docs/info.md`](docs/info.md) y [`README.md`](README.md)
- **`info.yaml`:** Configurado con `top_module: "tt_um_oscarc_507_mcp4921_spi"`, `clock_hz: 50000000`, `tiles: "1x1"`, `source_files` completo y mapeo de `ui[0..1]` y `uo[0..2]` manteniendo intactas las 24 claves del `pinout` y `yaml_version: 6`.
- **`docs/info.md` y `README.md`:** Documentación técnica del funcionamiento, mapeo de pines, instrucciones de prueba y conexión física al DAC MCP4921.
