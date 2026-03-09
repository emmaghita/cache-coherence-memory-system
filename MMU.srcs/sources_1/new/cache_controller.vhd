library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.MMU_package.all;

entity cache_ctrl is
  port(
    clk : in std_logic;
    rst : in std_logic;

    -- CPU  interface
    cpu_req   : in  std_logic;
    cpu_func  : in  std_logic; -- 0=read, 1=write
    cpu_addr  : in  std_logic_vector(ADDR_W-1 downto 0);
    cpu_wdata : in  std_logic_vector(7 downto 0);
    cpu_ready : out std_logic;

    -- from datapath
    hit         : in std_logic;
    state_out   : in msi_state_t;
    evict_dirty : in std_logic;
    evict_addr  : in std_logic_vector(ADDR_W-1 downto 0);
    evict_data  : in std_logic_vector(DATA_W-1 downto 0);

    -- to datapath
    dp_cpu_wr    : out std_logic;
    dp_install_en: out std_logic;
    dp_set_state : out std_logic;
    dp_new_state : out msi_state_t;
    dp_install_tag : out std_logic_vector(TAG_W-1 downto 0);
    dp_install_line: out std_logic_vector(DATA_W-1 downto 0);

    -- bus to memory ctrl
    bus_cmd_out  : out bus_cmd_t;
    bus_addr_out : out std_logic_vector(ADDR_W-1 downto 0);
    bus_data_out : out std_logic_vector(DATA_W-1 downto 0);

    -- response from memory ctrl
    bus_ready_in : in std_logic;
    bus_data_in  : in std_logic_vector(DATA_W-1 downto 0)
  );
end entity;

architecture rtl of cache_ctrl is
  type st_t is (IDLE, WB_WAIT, BUS_WAIT, COMPLETE);
  signal st : st_t := IDLE;

  -- latched cpu request
  signal r_func  : std_logic := '0';
  signal r_addr  : std_logic_vector(ADDR_W-1 downto 0) := (others=>'0');
  signal r_wdata : std_logic_vector(7 downto 0) := (others=>'0');

  -- tag extraction
  function get_tag(a: std_logic_vector(ADDR_W-1 downto 0)) return std_logic_vector is
  begin
    return a(ADDR_W-1 downto ADDR_W-TAG_W);
  end function;

begin

  process(clk)
    variable want_cmd : bus_cmd_t;
  begin
    if rising_edge(clk) then
      -- defaults
      cpu_ready      <= '0';

      dp_cpu_wr      <= '0';
      dp_install_en  <= '0';
      dp_set_state   <= '0';
      dp_new_state   <= MSI_I;
      dp_install_tag <= (others => '0');
      dp_install_line<= (others => '0');

      bus_cmd_out    <= BUS_NONE;
      bus_addr_out   <= (others => '0');
      bus_data_out   <= (others => '0');

      if rst='1' then
        st <= IDLE;
        r_func  <= '0';
        r_addr  <= (others=>'0');
        r_wdata <= (others=>'0');

      else
        case st is

          when IDLE =>
            -- wait for tb(cpu)request
            if cpu_req='1' then
              -- latch request once
              r_func  <= cpu_func;
              r_addr  <= cpu_addr;
              r_wdata <= cpu_wdata;

              -- HIT cases
              if hit='1' then
                if cpu_func='0' then
                  -- read hit: datapath already drives cpu_rdata combinationally
                  cpu_ready <= '1';
                  st <= IDLE;
                else
                  -- write hit
                  if state_out = MSI_M then
                    dp_cpu_wr    <= '1';
                    dp_set_state <= '1';
                    dp_new_state <= MSI_M;
                    cpu_ready <= '1';
                    st <= IDLE;
                  else
                    -- write hit in S => need ownership
                    bus_cmd_out  <= BUS_RDX;
                    bus_addr_out <= cpu_addr;
                    st <= BUS_WAIT;
                  end if;
                end if;

              else
                -- MISS: if victim dirty, WB first
                if evict_dirty='1' then
                  bus_cmd_out  <= BUS_WB;
                  bus_addr_out <= evict_addr;
                  bus_data_out <= evict_data;
                  st <= WB_WAIT;
                else
                  -- go directly request line
                  if cpu_func='0' then want_cmd := BUS_RD; else want_cmd := BUS_RDX; end if;
                  bus_cmd_out  <= want_cmd;
                  bus_addr_out <= cpu_addr;
                  st <= BUS_WAIT;
                end if;
              end if;
            end if;

          when WB_WAIT =>
            -- keep issuing WB until memory_ctrl ack
            bus_cmd_out  <= BUS_WB;
            bus_addr_out <= evict_addr;
            bus_data_out <= evict_data;
            if bus_ready_in='1' then
              -- now request the missed line
              if r_func='0' then want_cmd := BUS_RD; else want_cmd := BUS_RDX; end if;
              bus_cmd_out  <= want_cmd;
              bus_addr_out <= r_addr;
              st <= BUS_WAIT;
            end if;

          when BUS_WAIT =>
            -- keep issuing RD/RDX until ack + data
            if r_func='0' then want_cmd := BUS_RD; else want_cmd := BUS_RDX; end if;
            bus_cmd_out  <= want_cmd;
            bus_addr_out <= r_addr;

            if bus_ready_in='1' then
              -- install the received line
              dp_install_en   <= '1';
              dp_install_line <= bus_data_in;
              dp_install_tag  <= get_tag(r_addr);

              -- set MSI state after install
              dp_set_state <= '1';
              if r_func='0' then
                dp_new_state <= MSI_S;  -- MSI has no E
              else
                dp_new_state <= MSI_M;
                dp_cpu_wr    <= '1';    -- write-allocate: write after line arrives
              end if;

              st <= COMPLETE;
            end if;

          when COMPLETE =>
            cpu_ready <= '1';
            st <= IDLE;

        end case;
      end if;
    end if;
  end process;

end architecture;
