#include <stdio.h>
#include <dpmi.h>

int main(void)
{
	__dpmi_free_mem_info M;

	if (__dpmi_get_free_memory_information(&M) != 0) {
		printf("MI500: failed\n");
		return 1;
	}
	printf("MI500: largest %lu bytes, unlocked %lu, locked %lu, free %lu pages\n",
	       M.largest_available_free_block_in_bytes, M.maximum_unlocked_page_allocation_in_pages,
	       M.maximum_locked_page_allocation_in_pages, M.total_number_of_free_pages);
	return 0;
}
