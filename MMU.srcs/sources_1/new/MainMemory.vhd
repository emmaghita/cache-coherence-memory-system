library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.MMU_package.all;

entity MainMemory is
  port(
    clk          : in  std_logic;
    rst          : in  std_logic;
    mem_read     : in  std_logic;
    mem_write    : in  std_logic;
    mem_addr     : in  std_logic_vector(ADDR_W-1 downto 0);  -- byte address (aligned by controller)
    mem_data_in  : in  std_logic_vector(DATA_W-1 downto 0);  -- one line
    mem_data_out : out std_logic_vector(DATA_W-1 downto 0);  -- one line
    mem_ready    : out std_logic
  );
end entity;

architecture rtl of MainMemory is
  constant N_LINES : integer := 2**(ADDR_W - OFF_W);

  type mem_array_t is array (0 to N_LINES-1) of std_logic_vector(DATA_W-1 downto 0);
  signal memory : mem_array_t := (others => (others => '0'));

  signal line_addr : integer range 0 to N_LINES-1;
begin

  -- line index: drop OFF_W bits
  line_addr <= to_integer(unsigned(mem_addr(ADDR_W-1 downto OFF_W)));

  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then
        -- optional init pattern
        for i in 0 to N_LINES-1 loop
          memory(i) <= std_logic_vector(to_unsigned(i, DATA_W));
        end loop;

        mem_data_out <= (others => '0');
        mem_ready    <= '0';
      else
        mem_ready <= '0';

        if mem_write='1' then
          memory(line_addr) <= mem_data_in;
          mem_ready <= '1';

        elsif mem_read='1' then
          mem_data_out <= memory(line_addr);
          mem_ready <= '1';
        end if;
      end if;
    end if;
  end process;

end architecture;
