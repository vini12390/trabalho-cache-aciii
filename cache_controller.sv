// ============================================================
// cache_controller.sv
// Controlador de Cache — Trabalho Prático 1
// Baseado em Patterson & Hennessy, RISC-V Edition, Cap. 5
//
// Configuração:
//   - Cache diretamente mapeada (direct-mapped)
//   - 8 blocos, cada bloco com 4 palavras de 32 bits
//   - Política de escrita: Write-Back + Write-Allocate
//   - Endereços de 32 bits
//
// Organização dos bits de endereço (32 bits):
//   [31:7]  = tag      (25 bits)
//   [6:4]   = index    (3 bits  → 8 blocos)
//   [3:2]   = offset   (2 bits  → 4 palavras/bloco)
//   [1:0]   = byte     (ignorados — acesso word-aligned)
// ============================================================

`timescale 1ns/1ps

module cache_controller #(
    parameter NUM_SETS    = 8,     // Número de blocos (direto-mapeado)
    parameter BLOCK_WORDS = 4,     // Palavras por bloco
    parameter WORD_SIZE   = 32,    // Bits por palavra
    parameter ADDR_WIDTH  = 32,
    parameter INDEX_BITS  = 3,     // log2(NUM_SETS)
    parameter OFFSET_BITS = 2,     // log2(BLOCK_WORDS)
    parameter TAG_BITS    = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS - 2  // -2 byte offset
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Interface com o processador
    input  logic                  cpu_req,       // Requisição do processador
    input  logic                  cpu_we,        // Write enable (1=escrita, 0=leitura)
    input  logic [ADDR_WIDTH-1:0] cpu_addr,      // Endereço de 32 bits
    input  logic [WORD_SIZE-1:0]  cpu_wdata,     // Dado para escrita
    output logic [WORD_SIZE-1:0]  cpu_rdata,     // Dado lido (para o processador)
    output logic                  cpu_valid,     // Resposta pronta para o processador
    output logic                  cpu_stall,     // Stall — processador deve aguardar

    // Interface com a memória principal
    output logic                  mem_req,       // Requisição à memória
    output logic                  mem_we,        // Escrita na memória
    output logic [ADDR_WIDTH-1:0] mem_addr,      // Endereço na memória
    output logic [WORD_SIZE-1:0]  mem_wdata,     // Dado a escrever na memória
    input  logic [WORD_SIZE-1:0]  mem_rdata,     // Dado lido da memória
    input  logic                  mem_ready      // Memória pronta
);

    // -------------------------------------------------------
    // Estrutura da cache: arrays de metadados e dados
    // -------------------------------------------------------
    logic                   valid [0:NUM_SETS-1];
    logic                   dirty [0:NUM_SETS-1];
    logic [TAG_BITS-1:0]    tag   [0:NUM_SETS-1];
    logic [WORD_SIZE-1:0]   data  [0:NUM_SETS-1][0:BLOCK_WORDS-1];

    // -------------------------------------------------------
    // Decomposição do endereço
    // -------------------------------------------------------
    logic [TAG_BITS-1:0]    addr_tag;
    logic [INDEX_BITS-1:0]  addr_index;
    logic [OFFSET_BITS-1:0] addr_offset;

    assign addr_tag    = cpu_addr[ADDR_WIDTH-1 : ADDR_WIDTH-TAG_BITS];
    assign addr_index  = cpu_addr[ADDR_WIDTH-TAG_BITS-1 : ADDR_WIDTH-TAG_BITS-INDEX_BITS];
    assign addr_offset = cpu_addr[OFFSET_BITS+1 : 2];   // ignora 2 bits de byte

    // -------------------------------------------------------
    // Sinais de hit/miss
    // -------------------------------------------------------
    logic hit;
    assign hit = valid[addr_index] && (tag[addr_index] == addr_tag);

    // -------------------------------------------------------
    // FSM — Estados
    // -------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE        = 3'd0,  // Aguardando requisição
        READ_HIT    = 3'd1,  // Hit de leitura
        WRITE_HIT   = 3'd2,  // Hit de escrita
        WB_DIRTY    = 3'd3,  // Write-back do bloco sujo para memória
        FILL_REQ    = 3'd4,  // Solicitação de bloco à memória (miss)
        FILL_WAIT   = 3'd5,  // Aguardando dados da memória
        FILL_DONE   = 3'd6   // Bloco recebido, completa operação pendente
    } state_t;

    state_t state, next_state;

    // Contador de palavras durante operações de fill/wb
    logic [OFFSET_BITS-1:0] fill_cnt;
    logic [OFFSET_BITS-1:0] wb_cnt;

    // Salva a operação pendente durante miss
    logic                   pending_we;
    logic [WORD_SIZE-1:0]   pending_wdata;
    logic [ADDR_WIDTH-1:0]  pending_addr;

    // -------------------------------------------------------
    // Registrador de estado
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            fill_cnt <= '0;
            wb_cnt   <= '0;
        end else begin
            state <= next_state;

            // Captura informações da operação pendente ao entrar em miss
            if (state == IDLE && cpu_req && !hit) begin
                pending_we    <= cpu_we;
                pending_wdata <= cpu_wdata;
                pending_addr  <= cpu_addr;
            end

            // Incrementa contador de fill
            if (state == FILL_WAIT && mem_ready)
                fill_cnt <= fill_cnt + 1;
            else if (state == FILL_REQ)
                fill_cnt <= '0;

            // Incrementa contador de write-back
            if (state == WB_DIRTY && mem_ready)
                wb_cnt <= wb_cnt + 1;
            else if (state == IDLE)
                wb_cnt <= '0;
        end
    end

    // -------------------------------------------------------
    // Lógica de próximo estado
    // -------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        if (cpu_we) next_state = WRITE_HIT;
                        else        next_state = READ_HIT;
                    end else begin
                        // Miss: verificar se bloco atual é dirty
                        if (valid[addr_index] && dirty[addr_index])
                            next_state = WB_DIRTY;   // Precisa fazer write-back
                        else
                            next_state = FILL_REQ;   // Pode buscar diretamente
                    end
                end
            end

            READ_HIT:  next_state = IDLE;
            WRITE_HIT: next_state = IDLE;

            WB_DIRTY: begin
                // Aguarda write-back de todas as palavras do bloco
                if (mem_ready && wb_cnt == BLOCK_WORDS-1)
                    next_state = FILL_REQ;
            end

            FILL_REQ: next_state = FILL_WAIT;

            FILL_WAIT: begin
                if (mem_ready && fill_cnt == BLOCK_WORDS-1)
                    next_state = FILL_DONE;
            end

            FILL_DONE: next_state = IDLE;

            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------
    // Lógica de saída + atualização da cache (datapath)
    // -------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_SETS; i++) begin
                valid[i] <= 1'b0;
                dirty[i] <= 1'b0;
                tag[i]   <= '0;
            end
            cpu_rdata  <= '0;
            cpu_valid  <= 1'b0;
        end else begin
            cpu_valid <= 1'b0;  // default: sem resposta

            case (state)
                READ_HIT: begin
                    cpu_rdata <= data[addr_index][addr_offset];
                    cpu_valid <= 1'b1;
                end

                WRITE_HIT: begin
                    // Escrita no bloco — write-back policy
                    data[addr_index][addr_offset] <= cpu_wdata;
                    dirty[addr_index]             <= 1'b1;
                    cpu_valid                     <= 1'b1;
                end

                FILL_WAIT: begin
                    if (mem_ready) begin
                        // Armazena palavra recebida da memória
                        data[addr_index][fill_cnt] <= mem_rdata;
                    end
                end

                FILL_DONE: begin
                    // Finaliza preenchimento do bloco
                    valid[addr_index] <= 1'b1;
                    dirty[addr_index] <= 1'b0;
                    tag[addr_index]   <= pending_addr[ADDR_WIDTH-1 : ADDR_WIDTH-TAG_BITS];

                    // Se a operação pendente era escrita (write-allocate)
                    if (pending_we) begin
                        data[addr_index][pending_addr[OFFSET_BITS+1:2]] <= pending_wdata;
                        dirty[addr_index] <= 1'b1;
                    end
                    cpu_valid <= 1'b1;

                    // Dado de leitura
                    if (!pending_we)
                        cpu_rdata <= data[addr_index][pending_addr[OFFSET_BITS+1:2]];
                end

                default: ;
            endcase
        end
    end

    // -------------------------------------------------------
    // Saídas combinacionais
    // -------------------------------------------------------
    // Stall enquanto não está em IDLE, READ_HIT, WRITE_HIT ou FILL_DONE
    assign cpu_stall = cpu_req && !(state == IDLE && hit) &&
                       state != READ_HIT  &&
                       state != WRITE_HIT &&
                       state != FILL_DONE;

    // Requisição à memória
    always_comb begin
        mem_req   = 1'b0;
        mem_we    = 1'b0;
        mem_addr  = '0;
        mem_wdata = '0;

        case (state)
            WB_DIRTY: begin
                // Envia palavra do bloco sujo para memória
                mem_req   = 1'b1;
                mem_we    = 1'b1;
                mem_addr  = {tag[addr_index],
                             addr_index,
                             wb_cnt,
                             2'b00};
                mem_wdata = data[addr_index][wb_cnt];
            end

            FILL_REQ, FILL_WAIT: begin
                // Solicita leitura de bloco da memória
                mem_req  = 1'b1;
                mem_we   = 1'b0;
                mem_addr = {pending_addr[ADDR_WIDTH-1 : OFFSET_BITS+2],
                            fill_cnt,
                            2'b00};
            end

            default: ;
        endcase
    end

endmodule
