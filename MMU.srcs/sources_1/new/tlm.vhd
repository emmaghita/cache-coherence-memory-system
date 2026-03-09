library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.MMU_package.all;

entity tlm is
  port(
    clk : in std_logic;
    rst : in std_logic;

    -- CPU/Testbench interface for Cache 0
    c0_cpu_req   : in  std_logic;
    c0_cpu_func  : in  std_logic; -- 0=read, 1=write
    c0_cpu_addr  : in  std_logic_vector(ADDR_W-1 downto 0);
    c0_cpu_wdata : in  std_logic_vector(7 downto 0);
    c0_cpu_rdata : out std_logic_vector(7 downto 0);
    c0_cpu_ready : out std_logic;

    -- CPU/Testbench interface for Cache 1
    c1_cpu_req   : in  std_logic;
    c1_cpu_func  : in  std_logic;
    c1_cpu_addr  : in  std_logic_vector(ADDR_W-1 downto 0);
    c1_cpu_wdata : in  std_logic_vector(7 downto 0);
    c1_cpu_rdata : out std_logic_vector(7 downto 0);
    c1_cpu_ready : out std_logic
  );
end entity;

architecture rtl of tlm is

  -- Cache 0 <-> memory_ctrl bus
  signal c0_bus_cmd   : bus_cmd_t;
  signal c0_bus_addr  : std_logic_vector(ADDR_W-1 downto 0);
  signal c0_bus_wdata : std_logic_vector(DATA_W-1 downto 0);
  signal c0_bus_rdata : std_logic_vector(DATA_W-1 downto 0);
  signal c0_bus_ready : std_logic;
  signal c0_bus_shared: std_logic;

  -- Cache 0 snoop (from memory ctrl) + response (to memory ctrl)
  signal c0_snoop_valid : std_logic;
  signal c0_snoop_cmd   : bus_cmd_t;
  signal c0_snoop_addr  : std_logic_vector(ADDR_W-1 downto 0);
  signal c0_snoop_hit   : std_logic;
  signal c0_snoop_data  : std_logic_vector(DATA_W-1 downto 0);

  -- Cache 1 <-> memory_ctrl bus
  signal c1_bus_cmd   : bus_cmd_t;
  signal c1_bus_addr  : std_logic_vector(ADDR_W-1 downto 0);
  signal c1_bus_wdata : std_logic_vector(DATA_W-1 downto 0);
  signal c1_bus_rdata : std_logic_vector(DATA_W-1 downto 0);
  signal c1_bus_ready : std_logic;
  signal c1_bus_shared: std_logic;

  -- Cache 1 snoop
  signal c1_snoop_valid : std_logic;
  signal c1_snoop_cmd   : bus_cmd_t;
  signal c1_snoop_addr  : std_logic_vector(ADDR_W-1 downto 0);
  signal c1_snoop_hit   : std_logic;
  signal c1_snoop_data  : std_logic_vector(DATA_W-1 downto 0);

  -- memory_ctrl <-> main memory
  signal mem_read     : std_logic;
  signal mem_write    : std_logic;
  signal mem_addr     : std_logic_vector(ADDR_W-1 downto 0);
  signal mem_data_in  : std_logic_vector(DATA_W-1 downto 0);
  signal mem_data_out : std_logic_vector(DATA_W-1 downto 0);
  signal mem_ready    : std_logic;

begin
  -- Cache 0
  C0 : entity work.cache
    port map(
      clk => clk,
      rst => rst,

      cpu_req   => c0_cpu_req,
      cpu_func  => c0_cpu_func,
      cpu_addr  => c0_cpu_addr,
      cpu_wdata => c0_cpu_wdata,
      cpu_rdata => c0_cpu_rdata,
      cpu_ready => c0_cpu_ready,

      bus_cmd_out   => c0_bus_cmd,
      bus_addr_out  => c0_bus_addr,
      bus_data_out  => c0_bus_wdata,
      bus_data_in   => c0_bus_rdata,
      bus_ready_in  => c0_bus_ready,
      bus_shared_in => c0_bus_shared,

      snoop_valid => c0_snoop_valid,
      snoop_cmd   => c0_snoop_cmd,
      snoop_addr  => c0_snoop_addr,
      snoop_hit   => c0_snoop_hit,
      snoop_data  => c0_snoop_data
    );

  -- Cache 1
  C1 : entity work.cache
    port map(
      clk => clk,
      rst => rst,

      cpu_req   => c1_cpu_req,
      cpu_func  => c1_cpu_func,
      cpu_addr  => c1_cpu_addr,
      cpu_wdata => c1_cpu_wdata,
      cpu_rdata => c1_cpu_rdata,
      cpu_ready => c1_cpu_ready,

      bus_cmd_out   => c1_bus_cmd,
      bus_addr_out  => c1_bus_addr,
      bus_data_out  => c1_bus_wdata,
      bus_data_in   => c1_bus_rdata,
      bus_ready_in  => c1_bus_ready,
      bus_shared_in => c1_bus_shared,

      snoop_valid => c1_snoop_valid,
      snoop_cmd   => c1_snoop_cmd,
      snoop_addr  => c1_snoop_addr,
      snoop_hit   => c1_snoop_hit,
      snoop_data  => c1_snoop_data
    );

  -- Memory Controller (central snoopy bus)
  MC : entity work.memory_ctrl
    port map(
      clk => clk,
      rst => rst,

      -- Cache 0 requester side
      c0_bus_cmd_in   => c0_bus_cmd,
      c0_bus_addr_in  => c0_bus_addr,
      c0_bus_data_in  => c0_bus_wdata,
      c0_bus_data_out => c0_bus_rdata,
      c0_bus_ready    => c0_bus_ready,
      c0_bus_shared   => c0_bus_shared,

      -- Cache 0 snoop side
      c0_snoop_cmd    => c0_snoop_cmd,
      c0_snoop_addr   => c0_snoop_addr,
      c0_snoop_valid  => c0_snoop_valid,
      c0_snoop_data   => c0_snoop_data,
      c0_snoop_hit    => c0_snoop_hit,

      -- Cache 1 requester side
      c1_bus_cmd_in   => c1_bus_cmd,
      c1_bus_addr_in  => c1_bus_addr,
      c1_bus_data_in  => c1_bus_wdata,
      c1_bus_data_out => c1_bus_rdata,
      c1_bus_ready    => c1_bus_ready,
      c1_bus_shared   => c1_bus_shared,

      -- Cache 1 snoop side
      c1_snoop_cmd    => c1_snoop_cmd,
      c1_snoop_addr   => c1_snoop_addr,
      c1_snoop_valid  => c1_snoop_valid,
      c1_snoop_data   => c1_snoop_data,
      c1_snoop_hit    => c1_snoop_hit,

      -- Main memory side
      mem_read     => mem_read,
      mem_write    => mem_write,
      mem_addr     => mem_addr,
      mem_data_in  => mem_data_in,
      mem_data_out => mem_data_out,
      mem_ready    => mem_ready
    );
    
  -- main memory
  MEM : entity work.MainMemory
    port map(
      clk          => clk,
      rst          => rst,
      mem_read     => mem_read,
      mem_write    => mem_write,
      mem_addr     => mem_addr,
      mem_data_in  => mem_data_in,
      mem_data_out => mem_data_out,
      mem_ready    => mem_ready
    );

end architecture;
