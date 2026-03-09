library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.MMU_package.all;

entity cache is
  port(
    clk : in std_logic;
    rst : in std_logic;

    -- CPU / Testbench interface
    cpu_req   : in  std_logic;
    cpu_func  : in  std_logic; -- 0=read, 1=write
    cpu_addr  : in  std_logic_vector(ADDR_W-1 downto 0);
    cpu_wdata : in  std_logic_vector(7 downto 0);
    cpu_rdata : out std_logic_vector(7 downto 0);
    cpu_ready : out std_logic;

    -- Bus interface to memory_ctrl (this cache is a requester)
    bus_cmd_out  : out bus_cmd_t;
    bus_addr_out : out std_logic_vector(ADDR_W-1 downto 0);
    bus_data_out : out std_logic_vector(DATA_W-1 downto 0);

    bus_data_in  : in  std_logic_vector(DATA_W-1 downto 0);
    bus_ready_in : in  std_logic;
    bus_shared_in: in  std_logic;  -- not required for MSI baseline, but kept for compatibility

    -- Snoop interface from memory_ctrl (this cache is a snooper)
    snoop_valid : in  std_logic;
    snoop_cmd   : in  bus_cmd_t;
    snoop_addr  : in  std_logic_vector(ADDR_W-1 downto 0);

    snoop_hit   : out std_logic;
    snoop_data  : out std_logic_vector(DATA_W-1 downto 0)
  );
end entity;

architecture rtl of cache is

  -- DP <-> CTRL signals
  signal dp_hit        : std_logic;
  signal dp_state      : msi_state_t;
  signal dp_evict_dirty: std_logic;
  signal dp_evict_addr : std_logic_vector(ADDR_W-1 downto 0);
  signal dp_evict_data : std_logic_vector(DATA_W-1 downto 0);

  signal dp_cpu_wr     : std_logic;
  signal dp_install_en : std_logic;
  signal dp_set_state  : std_logic;
  signal dp_new_state  : msi_state_t;

  signal dp_install_tag : std_logic_vector(TAG_W-1 downto 0);
  signal dp_install_line: std_logic_vector(DATA_W-1 downto 0);

begin

  -- Datapath
  U_DP : entity work.cache_datapath
    port map(
      clk         => clk,

      p_addr      => cpu_addr,
      p_wdata     => cpu_wdata,
      p_rdata     => cpu_rdata,

      cpu_wr      => dp_cpu_wr,
      install_en  => dp_install_en,
      install_line=> dp_install_line,
      install_tag => dp_install_tag,

      set_state   => dp_set_state,
      new_state   => dp_new_state,

      hit         => dp_hit,
      state_out   => dp_state,
      evict_dirty => dp_evict_dirty,
      evict_addr  => dp_evict_addr,
      evict_data  => dp_evict_data,

      snoop_valid => snoop_valid,
      snoop_cmd   => snoop_cmd,
      snoop_addr  => snoop_addr,

      snoop_hit   => snoop_hit,
      snoop_data  => snoop_data
    );

  -- Controller
  U_CTRL : entity work.cache_ctrl
    port map(
      clk => clk,
      rst => rst,

      cpu_req   => cpu_req,
      cpu_func  => cpu_func,
      cpu_addr  => cpu_addr,
      cpu_wdata => cpu_wdata,
      cpu_ready => cpu_ready,

      hit         => dp_hit,
      state_out   => dp_state,
      evict_dirty => dp_evict_dirty,
      evict_addr  => dp_evict_addr,
      evict_data  => dp_evict_data,

      dp_cpu_wr      => dp_cpu_wr,
      dp_install_en  => dp_install_en,
      dp_set_state   => dp_set_state,
      dp_new_state   => dp_new_state,
      dp_install_tag => dp_install_tag,
      dp_install_line=> dp_install_line,

      bus_cmd_out  => bus_cmd_out,
      bus_addr_out => bus_addr_out,
      bus_data_out => bus_data_out,

      bus_ready_in => bus_ready_in,
      bus_data_in  => bus_data_in
    );

end architecture;
