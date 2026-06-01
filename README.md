# Cache Controller — Trabalho Prático 1

Implementação em **SystemVerilog** de um controlador de cache diretamente mapeada (direct-mapped), com política de escrita **Write-Back + Write-Allocate**, baseado no Capítulo 5 do livro *Computer Organization and Design: RISC-V Edition* (Patterson & Hennessy).

---

## Arquitetura

| Parâmetro | Valor |
|---|---|
| Tipo de mapeamento | Direct-mapped |
| Número de conjuntos | 8 |
| Palavras por bloco | 4 × 32 bits |
| Política de escrita | Write-Back |
| Política de miss de escrita | Write-Allocate |
| Largura do endereço | 32 bits |

### Organização dos bits de endereço

```
[31:7]  = tag    (25 bits)
[6:4]   = index  ( 3 bits)
[3:2]   = offset ( 2 bits)
[1:0]   = byte   (ignorado — acesso word-aligned)
```

---

## Estrutura do repositório

```
.
├── src/
│   └── cache_controller.sv     # Módulo principal
├── tb/
│   └── tb_cache_controller.sv  # Testbench completo
├── sim/
│   └── run_sim.sh              # Script de simulação (Icarus Verilog)
└── README.md
```

---

## Dependências

- **Icarus Verilog** ≥ 11 (ou ModelSim/Questa/Verilator)
- **GTKWave** (opcional, para visualizar waveforms)

### Instalação no Ubuntu/Debian

```bash
sudo apt update
sudo apt install iverilog gtkwave -y
```

---

## Compilação e Simulação

### Com Icarus Verilog

```bash
# Compilar
iverilog -g2012 -o sim_cache src/cache_controller.sv tb/tb_cache_controller.sv

# Executar simulação
vvp sim_cache

# Visualizar waveforms (opcional)
gtkwave dump.vcd
```

### Com o script automático

```bash
chmod +x sim/run_sim.sh
./sim/run_sim.sh
```

---

## Resultados esperados

```
========== 7.5 Estado inicial (cache vazia) ==========
[PASS] Inicializacao cache vazia addr=0 ...

========== 7.1 Testes de Leitura ==========
[PASS] Read MISS  addr=0x10 ...
[PASS] Read HIT   addr=0x10 (repetido) ...
...

RESULTADO FINAL: 20 PASS | 0 FAIL
>>> Todos os testes passaram com sucesso! <<<
```

---

## Integrantes

- Vinícius Figueiredo
- Gustavo Vinícius

---

## Referências

- Patterson, D. A.; Hennessy, J. L. *Computer Organization and Design: The Hardware/Software Interface — RISC-V Edition*. Morgan Kaufmann, 2017. Cap. 5, Seção 5.12.
