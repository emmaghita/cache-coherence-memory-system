library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.MMU_package.all;

entity cache_datapath is
  port(
    clk : in std_logic;

    -- CPU
    p_addr  : in  std_logic_vector(ADDR_W-1 downto 0);
    p_wdata : in  std_logic_vector(7 downto 0);
    p_rdata : out std_logic_vector(7 downto 0);

    -- Control from controller
    cpu_wr       : in std_logic;
    install_en   : in std_logic;
    install_line : in std_logic_vector(DATA_W-1 downto 0);
    install_tag  : in std_logic_vector(TAG_W-1 downto 0);
    set_state    : in std_logic;
    new_state    : in msi_state_t;

    -- Status to controller
    hit         : out std_logic;
    state_out   : out msi_state_t;
    evict_dirty : out std_logic;
    evict_addr  : out std_logic_vector(ADDR_W-1 downto 0);
    evict_data  : out std_logic_vector(DATA_W-1 downto 0);

    -- Snoop from memory_ctrl
    snoop_valid : in std_logic;
    snoop_cmd   : in bus_cmd_t;
    snoop_addr  : in std_logic_vector(ADDR_W-1 downto 0);

    -- Snoop response
    snoop_hit   : out std_logic;
    snoop_data  : out std_logic_vector(DATA_W-1 downto 0)
  );
end entity;

architecture rtl of cache_datapath is
  constant N_LINES : integer := 2**IDX_W;

  type data_arr_t is array (0 to N_LINES-1) of std_logic_vector(DATA_W-1 downto 0);
  type tag_arr_t  is array (0 to N_LINES-1) of std_logic_vector(TAG_W-1 downto 0);
  type st_arr_t   is array (0 to N_LINES-1) of msi_state_t;

  signal data_mem : data_arr_t := (others => (others => '0'));
  signal tag_mem  : tag_arr_t  := (others => (others => '0'));
  signal st_mem   : st_arr_t   := (others => MSI_I);

  -- CPU decode
  signal cpu_tag   : std_logic_vector(TAG_W-1 downto 0);
  signal cpu_idx   : integer range 0 to N_LINES-1;
  signal cpu_off   : std_logic_vector(OFF_W-1 downto 0);
  signal tag_match : std_logic;

  constant ZERO_OFF : std_logic_vector(OFF_W-1 downto 0) := (others => '0');

begin
  -- address layout: [tag|index|offset]
  cpu_tag <= p_addr(ADDR_W-1 downto ADDR_W-TAG_W);
  cpu_idx <= to_integer(unsigned(p_addr(OFF_W+IDX_W-1 downto OFF_W)));
  cpu_off <= p_addr(OFF_W-1 downto 0);

  tag_match <= '1' when tag_mem(cpu_idx) = cpu_tag else '0';

  hit       <= '1' when (st_mem(cpu_idx) /= MSI_I and tag_match='1') else '0';
  state_out <= st_mem(cpu_idx);

  evict_dirty <= '1' when st_mem(cpu_idx) = MSI_M else '0';
  evict_data  <= data_mem(cpu_idx);

  -- victim address
  evict_addr <= tag_mem(cpu_idx)
               & std_logic_vector(to_unsigned(cpu_idx, IDX_W))
               & ZERO_OFF;

  -- CPU read 
  cpu_read_p : process(cpu_idx, cpu_off, data_mem)
    variable line : std_logic_vector(DATA_W-1 downto 0);
  begin
    line := data_mem(cpu_idx);
    case cpu_off is
      when "00" => p_rdata <= line(31 downto 24);
      when "01" => p_rdata <= line(23 downto 16);
      when "10" => p_rdata <= line(15 downto 8);
      when others => p_rdata <= line(7 downto 0);
    end case;
  end process;

  -- Sequential updates
  seq_p : process(clk)
    variable sn_tag   : std_logic_vector(TAG_W-1 downto 0);
    variable sn_idx   : integer range 0 to N_LINES-1;
    variable sn_match : boolean;
  begin
    if rising_edge(clk) then

      if install_en='1' then
        data_mem(cpu_idx) <= install_line;
        tag_mem(cpu_idx)  <= install_tag;
      end if;

      if cpu_wr='1' then
        case cpu_off is
          when "00" => data_mem(cpu_idx)(31 downto 24) <= p_wdata;
          when "01" => data_mem(cpu_idx)(23 downto 16) <= p_wdata;
          when "10" => data_mem(cpu_idx)(15 downto 8)  <= p_wdata;
          when others => data_mem(cpu_idx)(7 downto 0)  <= p_wdata;
        end case;
      end if;

      if set_state='1' then
        st_mem(cpu_idx) <= new_state;
      end if;

      -- snoop state transitions
      if snoop_valid='1' then
        sn_tag := snoop_addr(ADDR_W-1 downto ADDR_W-TAG_W);
        sn_idx := to_integer(unsigned(snoop_addr(OFF_W+IDX_W-1 downto OFF_W)));
        sn_match := (st_mem(sn_idx) /= MSI_I) and (tag_mem(sn_idx) = sn_tag);

        if sn_match then
          case snoop_cmd is
            when BUS_RD =>
              if st_mem(sn_idx) = MSI_M then
                st_mem(sn_idx) <= MSI_S;
              end if;

            when BUS_RDX =>
              st_mem(sn_idx) <= MSI_I;

            when others =>
              null;
          end case;
        end if;
      end if;

    end if;
  end process;

  -- Snoop response
  snoop_p : process(snoop_valid, snoop_addr, tag_mem, st_mem, data_mem)
    variable sn_tag   : std_logic_vector(TAG_W-1 downto 0);
    variable sn_idx   : integer range 0 to N_LINES-1;
    variable sn_match : boolean;
  begin
    sn_tag := snoop_addr(ADDR_W-1 downto ADDR_W-TAG_W);
    sn_idx := to_integer(unsigned(snoop_addr(OFF_W+IDX_W-1 downto OFF_W)));
    sn_match := (st_mem(sn_idx) /= MSI_I) and (tag_mem(sn_idx) = sn_tag);

    if snoop_valid='1' and sn_match then
      snoop_hit  <= '1';
      snoop_data <= data_mem(sn_idx);
    else
      snoop_hit  <= '0';
      snoop_data <= (others => '0');
    end if;
  end process;

end architecture;
