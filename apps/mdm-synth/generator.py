import os, sys
import random, time
import logging

from faker import Faker
import csv

logger = logging.getLogger(__name__)

def generateCustomerTable(filename, rowcount = 100): 
  faker = Faker('en_US')
  Faker.seed(time.time_ns())

  # list of tuples(3)
  field_map = [
    ('id', None, None), 
    ('first_name', 'first_name', None), 
    ('last_name', 'last_name', None), 
    ('dob', 'date_of_birth', {"minimum_age": 18, "maximum_age": 99}), 
    ('citizenship', None, '"USA" if random.random() < 0.95 else faker.country_code(representation="alpha-3")'), 
    ('marital_status', 'random_element', ['single', 'married', 'divorced', 'widowed']), 
  ]

  headers = [elem[0] for elem in field_map]
  with open(filename, 'wt') as csv_file: 
    writer = csv.DictWriter(csv_file, fieldnames = headers)
    writer.writeheader()

    for i in range(0, rowcount): 
      record = {'id': i} # id is required for glue crawler to detect schema
      for field in field_map: 
        col_name = field[0]
        faker_func = field[1]
        py_expr = field[2] 

        if faker_func is None: 
          if py_expr is None: 
            continue
          else: 
            col_value = eval(py_expr)
        else: 
          fx = getattr(faker, faker_func)
          col_value = fx(**py_expr) if isinstance(py_expr, dict) else fx(py_expr)
        
        record[col_name] = col_value
      writer.writerow(record)

if __name__ == '__main__':
  generateCustomerTable('../../data/synth/mdm/customer/customer.csv', 100)

