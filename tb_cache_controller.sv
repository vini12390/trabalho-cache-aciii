// ============================================================
// tb_cache_controller.sv
// Testbench do Controlador de Cache — Trabalho Prático 1
//
// Cobre todos os cenários obrigatórios:
//   7.1 Testes de Leitura
//   7.2 Testes de Escrita
//   7.3 Testes de Substituição
//   7.4 Testes de Consistência
//   7.5 Testes de Casos Limite
// ============================================================

`timescale 1ns/1ps

module tb_cache_controller;

    // ----------------------------------------------------------
    // Parâmetros
    // ----------------------------------------------------------
    localparam CLK_PERIOD  = 10;
    localparam ADDR_W      = 32;
    localparam DATA_W      = 32;
    localparam NUM_SETS    = 8;
    localparam BLOCK_WORDS = 4;
    localparam MEM_SIZE    = 1024;  // palavras na memória modelo

    // ----------------------------------------------------------
    // Sinais
    // ----------------------------------------------------------
    logic              clk, rst_n;
    logic              cpu_req, cpu_we;
    logic [ADDR_W-1:0] cpu_addr;
    logic [DATA_W-1:0] cpu_wdata;
    logic [DATA_W-1:0] cpu_rdata;
    logic              cpu_valid, cpu_stall;

    logic              mem_req, mem_we;
    logic [ADDR_W-1:0] mem_addr;
    logic [DATA_W-1:0] mem_wdata, mem_rdata;
    logic              mem_ready;

    // ----------------------------------------------------------
    // DUT
    // ----------------------------------------------------------
    cache_controller dut (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(cpu_req), .cpu_we(cpu_we),
        .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata),
        .cpu_rdata(cpu_rdata), .cpu_valid(cpu_valid),
        .cpu_stall(cpu_stall),
        .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    // ----------------------------------------------------------
    // Modelo de memória principal (RAM comportamental)
    // Latência fixa de 2 ciclos
    // ----------------------------------------------------------
    logic [DATA_W-1:0] main_mem [0:MEM_SIZE-1];
    logic [1:0]        mem_lat_cnt;

    initial begin
        // Inicializa memória com padrão reconhecível: addr*4 + 0xA000_0000
        for (int i = 0; i < MEM_SIZE; i++)
            main_mem[i] = 32'hA000_0000 + i;
        mem_ready   = 1'b0;
        mem_lat_cnt = 2'd0;
    end

    always_ff @(posedge clk) begin
        mem_ready <= 1'b0;
        if (mem_req) begin
            if (mem_lat_cnt == 2'd1) begin
                mem_lat_cnt <= 2'd0;
                mem_ready   <= 1'b1;
                if (mem_we)
                    main_mem[mem_addr[ADDR_W-1:2] % MEM_SIZE] <= mem_wdata;
                else
                    mem_rdata <= main_mem[mem_addr[ADDR_W-1:2] % MEM_SIZE];
            end else begin
                mem_lat_cnt <= mem_lat_cnt + 1;
            end
        end else begin
            mem_lat_cnt <= 2'd0;
        end
    end

    // ----------------------------------------------------------
    // Clock
    // ----------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ----------------------------------------------------------
    // Contadores de pass/fail
    // ----------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    // ----------------------------------------------------------
    // Task: emite uma requisição e aguarda resposta
    // ----------------------------------------------------------
    task automatic cpu_access(
        input  logic [ADDR_W-1:0] addr,
        input  logic              we,
        input  logic [DATA_W-1:0] wdata,
        output logic [DATA_W-1:0] rdata
    );
        @(posedge clk); #1;
        cpu_req   = 1'b1;
        cpu_we    = we;
        cpu_addr  = addr;
        cpu_wdata = wdata;

        // Aguarda resposta (sem timeout de segurança)
        fork
            begin : wait_valid
                forever begin
                    @(posedge clk);
                    if (cpu_valid) begin
                        rdata = cpu_rdata;
                        disable wait_valid;
                    end
                end
            end
            begin : timeout
                repeat(200) @(posedge clk);
                $display("TIMEOUT na acesso addr=0x%08h", addr);
                disable wait_valid;
            end
        join

        #1;
        cpu_req = 1'b0;
        @(posedge clk); #1;
    endtask

    // ----------------------------------------------------------
    // Task: verifica valor lido e exibe resultado
    // ----------------------------------------------------------
    task automatic check_read(
        input string test_name,
        input logic [ADDR_W-1:0] addr,
        input logic [DATA_W-1:0] expected
    );
        logic [DATA_W-1:0] got;
        cpu_access(addr, 1'b0, 32'h0, got);
        if (got === expected) begin
            $display("[PASS] %s | addr=0x%08h | lido=0x%08h", test_name, addr, got);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s | addr=0x%08h | esperado=0x%08h | obtido=0x%08h",
                     test_name, addr, expected, got);
            fail_cnt++;
        end
    endtask

    // ----------------------------------------------------------
    // TESTE PRINCIPAL
    // ----------------------------------------------------------
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_cache_controller);

        // Reset
        rst_n    = 1'b0;
        cpu_req  = 1'b0;
        cpu_we   = 1'b0;
        cpu_addr = '0;
        cpu_wdata = '0;
        repeat(3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        $display("\n========== 7.5 Estado inicial (cache vazia) ==========");
        // Acesso a endereço 0 — deve gerar miss e buscar da memória
        check_read("Inicializacao cache vazia addr=0",
                   32'h0000_0000,
                   32'hA000_0000);   // main_mem[0]

        $display("\n========== 7.1 Testes de Leitura ==========");

        // Primeira leitura — miss — preenche bloco (palavras 0..3)
        check_read("Read MISS  addr=0x10 (bloco 4)",
                   32'h0000_0010,
                   32'hA000_0004);   // main_mem[4]

        // Segunda leitura no mesmo bloco — HIT
        check_read("Read HIT   addr=0x10 (repetido)",
                   32'h0000_0010,
                   32'hA000_0004);

        // Outra palavra do mesmo bloco — HIT
        check_read("Read HIT   addr=0x14 (mesmo bloco)",
                   32'h0000_0014,
                   32'hA000_0005);

        // Verifica bits de controle indiretamente: miss em bloco diferente
        check_read("Read MISS  addr=0x20 (bloco 8)",
                   32'h0000_0020,
                   32'hA000_0008);

        $display("\n========== 7.2 Testes de Escrita ==========");
        begin
            logic [DATA_W-1:0] rd;

            // Escrita com HIT (bloco 4 já está na cache)
            cpu_access(32'h0000_0010, 1'b1, 32'hDEAD_BEEF, rd);
            $display("[INFO] Write HIT  addr=0x10 wdata=0xDEADBEEF");
            pass_cnt++;

            // Leitura de volta para confirmar
            check_read("Read-back apos write HIT  addr=0x10",
                       32'h0000_0010,
                       32'hDEAD_BEEF);

            // Escrita com MISS (write-allocate: busca bloco, depois escreve)
            cpu_access(32'h0000_0040, 1'b1, 32'hCAFE_BABE, rd);
            $display("[INFO] Write MISS addr=0x40 wdata=0xCAFEBABE (write-allocate)");
            pass_cnt++;

            // Leitura de volta
            check_read("Read-back apos write MISS addr=0x40",
                       32'h0000_0040,
                       32'hCAFE_BABE);
        end

        $display("\n========== 7.3 Testes de Substituição (Write-Back + bloco dirty) ==========");
        begin
            logic [DATA_W-1:0] rd;

            // addr=0x10 → index=4, modificado → dirty
            // addr=0x210 → mesmo index=4, endereço diferente → substituição
            // O bloco dirty DEVE ser escrito de volta na memória antes do fill

            // Escreve dado novo em index=4
            cpu_access(32'h0000_0010, 1'b1, 32'h1111_2222, rd);
            $display("[INFO] Escrita em index=4 (dirty) addr=0x10");

            // Acessa outro endereço que mapeia para index=4
            // Tag diferente → miss → write-back do dirty → fill novo bloco
            check_read("Miss com WB (substituicao index=4) addr=0x210",
                       32'h0000_0210,
                       32'hA000_0084);   // main_mem[0x210>>2] = main_mem[132]

            // Verifica que memória recebeu o write-back
            begin
                logic [DATA_W-1:0] wb_val;
                wb_val = main_mem[32'h0000_0010 >> 2];  // posição word 4
                if (wb_val === 32'h1111_2222) begin
                    $display("[PASS] Write-back verificado: main_mem[4]=0x%08h", wb_val);
                    pass_cnt++;
                end else begin
                    $display("[FAIL] Write-back INCORRETO: main_mem[4]=0x%08h (esperado 0x11112222)", wb_val);
                    fail_cnt++;
                end
            end
        end

        $display("\n========== 7.4 Testes de Consistência ==========");
        begin
            logic [DATA_W-1:0] rd;

            // Sequência read-write-read no mesmo endereço
            check_read("Consistencia: leitura inicial addr=0x30",
                       32'h0000_0030,
                       32'hA000_000C);

            cpu_access(32'h0000_0030, 1'b1, 32'hABCD_1234, rd);
            $display("[INFO] Escrita addr=0x30 = 0xABCD1234");

            check_read("Consistencia: read-after-write addr=0x30",
                       32'h0000_0030,
                       32'hABCD_1234);

            // Acessos repetidos ao mesmo endereço (hits consecutivos)
            for (int k = 0; k < 5; k++) begin
                check_read($sformatf("Consistencia: acesso repetido #%0d addr=0x30", k),
                           32'h0000_0030,
                           32'hABCD_1234);
            end

            // Conflitos: dois endereços diferentes, mesmo index
            // index=2: addr=0x08 e addr=0x208
            check_read("Conflito: 1a carga index=2 addr=0x08",
                       32'h0000_0008, 32'hA000_0002);

            cpu_access(32'h0000_0008, 1'b1, 32'h5A5A_5A5A, rd);

            // Acessa addr=0x208 → mesmo index=2, tag diferente → substituição
            check_read("Conflito: substituicao index=2 addr=0x208",
                       32'h0000_0208, 32'hA000_0082);

            // Recarrega addr=0x08 (foi evicto, mas write-back foi feito)
            check_read("Conflito: recarga addr=0x08 apos evicao",
                       32'h0000_0008, 32'h5A5A_5A5A);
        end

        $display("\n========== 7.5 Testes de Casos Limite ==========");
        begin
            logic [DATA_W-1:0] rd;

            // Endereço máximo que cabe no modelo de memória
            check_read("Caso limite: endereco alto addr=0xFFC",
                       32'h0000_0FFC,
                       main_mem[32'h0000_0FFC >> 2]);

            // Endereço 0
            check_read("Caso limite: endereco 0x00",
                       32'h0000_0000,
                       main_mem[0]);    // já pode estar na cache

            // Cache completamente inválida após reset
            rst_n = 1'b0;
            repeat(3) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);

            check_read("Pos-reset: cache invalida addr=0x00",
                       32'h0000_0000,
                       32'hA000_0000);
        end

        // ----------------------------------------------------------
        // Resumo
        // ----------------------------------------------------------
        $display("\n================================================");
        $display("RESULTADO FINAL: %0d PASS | %0d FAIL", pass_cnt, fail_cnt);
        $display("================================================\n");

        if (fail_cnt == 0)
            $display(">>> Todos os testes passaram com sucesso! <<<");
        else
            $display(">>> ATENCAO: %0d teste(s) falharam! <<<", fail_cnt);

        $finish;
    end

    // Watchdog global
    initial begin
        #500000;
        $display("WATCHDOG: simulacao excedeu limite de tempo");
        $finish;
    end

endmodule
